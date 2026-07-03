import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/http/custom_headers_provider.dart';
import '../../../core/http/http_client_provider.dart';
import '../../../core/logging/app_network_logger_provider.dart';
import '../../../core/logging/network_logger.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../domain/models/chat_message.dart';
import 'chat_chunk_parser.dart';
import 'chat_completion_client.dart';
import 'vendor_payload_adapters.dart';

/// OpenAI 兼容接口的 HTTP 流式客户端提供者。
final chatCompletionClientProvider = Provider<ChatCompletionClient>((ref) {
  final httpClient = ref.read(httpClientProvider);
  final logger = ref.watch(appNetworkLoggerProvider);
  // 在请求构建阶段获取自定义 header，确保在 logRequest 之前已附加到请求上。
  Map<String, String> extraHeadersFactory() =>
      ref.read(customHeadersMapProvider);
  return OpenAiCompatibleChatClient(
    httpClient: httpClient,
    logger: logger,
    extraHeadersFactory: extraHeadersFactory,
  );
});

/// 直接使用 HTTP 请求读取 SSE 流，并把返回内容拆成补全增量。
class OpenAiCompatibleChatClient implements ChatCompletionClient {
  OpenAiCompatibleChatClient({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
    VendorPayloadAdapterRegistry adapters =
        VendorPayloadAdapterRegistry.standard,
    Map<String, String> Function()? extraHeadersFactory,
  }) : _httpClient = httpClient,
       _logger = logger,
       _adapters = adapters,
       _extraHeadersFactory = extraHeadersFactory;

  final http.Client _httpClient;
  final NetworkLogger _logger;
  final VendorPayloadAdapterRegistry _adapters;
  final Map<String, String> Function()? _extraHeadersFactory;
  static const _parser = ChatChunkParser();

  @override
  /// 发送流式请求并把 SSE 事件转换为内容与推理增量。
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async* {
    final requestContext = _buildRequestContext(
      modelConfig: modelConfig,
      messages: messages,
      reasoningEffort: reasoningEffort,
      stream: true,
    );
    final response = await _sendRequest(requestContext);

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final dataLines = <String>[];
    final inlineReasoningSplitter = InlineReasoningTagSplitter();

    // SSE 事件以空行分隔；这里先收集 data 行，再按事件边界解析。
    await for (final line in lineStream) {
      if (line.isEmpty) {
        final chunk = _consumeEventData(dataLines);
        if (chunk == null) {
          continue;
        }
        if (chunk == _doneMarker) {
          break;
        }

        try {
          final parsed = _parser.parseRawChunk(
            chunk,
            inlineReasoningSplitter: inlineReasoningSplitter,
          );
          if (parsed != null) {
            yield parsed;
          }
        } catch (error, stackTrace) {
          _fireAndForget(
            _logger.logError(
              uri: requestContext.uri,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          rethrow;
        }
        continue;
      }

      if (line.startsWith('data:')) {
        final dataLine = line.substring(5).trimLeft();
        dataLines.add(dataLine);
        _fireAndForget(
          _logger.logSseLine(uri: requestContext.uri, line: dataLine),
        );
      }
    }

    final trailingChunk = _consumeEventData(dataLines);
    if (trailingChunk != null && trailingChunk != _doneMarker) {
      try {
        final parsed = _parser.parseRawChunk(
          trailingChunk,
          inlineReasoningSplitter: inlineReasoningSplitter,
        );
        if (parsed != null) {
          yield parsed;
        }
      } catch (error, stackTrace) {
        _fireAndForget(
          _logger.logError(
            uri: requestContext.uri,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        rethrow;
      }
    }

    final trailingInlineReasoning = inlineReasoningSplitter.flushRemainder();
    if (trailingInlineReasoning != null && !trailingInlineReasoning.isEmpty) {
      yield trailingInlineReasoning;
    }
  }

  @override
  Future<ChatCompletionResult> complete({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async {
    final requestContext = _buildRequestContext(
      modelConfig: modelConfig,
      messages: messages,
      reasoningEffort: reasoningEffort,
      stream: false,
    );
    final response = await _sendRequest(requestContext);
    final responseBody = await response.stream.bytesToString();
    _fireAndForget(
      _logger.logResponseBody(
        uri: requestContext.uri,
        body: _decodeResponseBodyForLogging(responseBody),
      ),
    );
    final parsed = _parser.parseRawChunk(
      responseBody,
      inlineReasoningSplitter: InlineReasoningTagSplitter(),
    );
    if (parsed == null) {
      return const ChatCompletionResult();
    }
    return ChatCompletionResult(
      content: parsed.contentDelta,
      reasoningContent: parsed.reasoningDelta,
    );
  }

  static const _doneMarker = '[DONE]';

  void _fireAndForget(Future<void> future) {
    unawaited(future);
  }

  Object _decodeResponseBodyForLogging(String responseBody) {
    final trimmed = responseBody.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  /// 合并当前事件的 data 行；空事件直接丢弃。
  String? _consumeEventData(List<String> dataLines) {
    if (dataLines.isEmpty) {
      return null;
    }

    final eventData = dataLines.join('\n').trim();
    dataLines.clear();

    if (eventData.isEmpty) {
      return null;
    }

    return eventData;
  }

  _OpenAiRequestContext _buildRequestContext({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    required bool stream,
    ReasoningEffort? reasoningEffort,
  }) {
    Uri uri;
    try {
      uri = Uri.parse(modelConfig.apiUrl);
    } on FormatException catch (e) {
      throw ChatCompletionException('API URL 格式无效：${e.message}');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ChatCompletionException(
        'API URL 协议不支持（需要 http/https）：${modelConfig.apiUrl}',
      );
    }

    final patch = _adapters.resolve(uri.host).buildPatch(reasoningEffort);
    final payload = <String, Object>{
      'model': modelConfig.modelName,
      'stream': stream,
      'messages': messages.map((message) => message.toJson()).toList(),
      if (reasoningEffort != null && !patch.skipStandardReasoningEffort)
        'reasoning_effort': reasoningEffort.apiValue,
    };
    if (patch.thinkingConfig != null) {
      payload['thinking'] = patch.thinkingConfig!;
    }
    if (patch.extraBody != null) {
      payload['extra_body'] = patch.extraBody!;
    }

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': stream ? 'text/event-stream' : 'application/json',
        'Authorization': 'Bearer ${modelConfig.apiKey}',
      })
      ..body = jsonEncode(payload);

    // 读取自定义 header 供日志使用；实际注入由 CustomHeadersHttpClient.send() 统一处理。
    final extraHeaders = _extraHeadersFactory?.call() ?? const {};

    return _OpenAiRequestContext(
      uri: uri,
      payload: payload,
      request: request,
      extraHeaders: extraHeaders,
    );
  }

  Future<http.StreamedResponse> _sendRequest(
    _OpenAiRequestContext context,
  ) async {
    _fireAndForget(
      _logger.logRequest(
        uri: context.uri,
        method: context.request.method,
        // 合并自定义 header 以便日志完整反映实际发出的请求头。
        headers: {
          ...context.request.headers,
          ...context.extraHeaders,
        },
        payload: context.payload,
      ),
    );

    final requestStartedAt = DateTime.now();
    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(context.request);
    } catch (error, stackTrace) {
      _fireAndForget(
        _logger.logError(
          uri: context.uri,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }

    _fireAndForget(
      _logger.logResponse(
        uri: context.uri,
        statusCode: response.statusCode,
        headers: response.headers,
        elapsed: DateTime.now().difference(requestStartedAt),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      _fireAndForget(
        _logger.logError(
          uri: context.uri,
          error:
              'HTTP ${response.statusCode}: ${responseBody.trim().isEmpty ? "服务端未返回错误详情" : responseBody.trim()}',
        ),
      );
      throw ChatCompletionException(
        '请求失败（${response.statusCode}）：${responseBody.trim().isEmpty ? "服务端未返回错误详情" : responseBody.trim()}',
      );
    }

    return response;
  }
}

class _OpenAiRequestContext {
  const _OpenAiRequestContext({
    required this.uri,
    required this.payload,
    required this.request,
    this.extraHeaders = const {},
  });

  final Uri uri;
  final Map<String, Object> payload;
  final http.Request request;
  final Map<String, String> extraHeaders;
}
