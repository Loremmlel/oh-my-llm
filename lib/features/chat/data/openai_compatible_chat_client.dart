import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_network_logger_provider.dart';
import '../../../core/logging/network_logger.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../domain/models/chat_message.dart';
import 'chat_chunk_parser.dart';
import 'chat_completion_client.dart';
import 'vendor_payload_adapters.dart';

/// OpenAI 兼容接口的 HTTP 流式客户端提供者。
final chatCompletionClientProvider = Provider<ChatCompletionClient>((ref) {
  final httpClient = http.Client();
  ref.onDispose(httpClient.close);
  final logger = ref.watch(appNetworkLoggerProvider);
  return OpenAiCompatibleChatClient(httpClient: httpClient, logger: logger);
});

/// 直接使用 HTTP 请求读取 SSE 流，并把返回内容拆成补全增量。
class OpenAiCompatibleChatClient implements ChatCompletionClient {
  OpenAiCompatibleChatClient({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
    VendorPayloadAdapterRegistry adapters = VendorPayloadAdapterRegistry.standard,
  }) : _httpClient = httpClient,
       _logger = logger,
       _adapters = adapters;

  final http.Client _httpClient;
  final NetworkLogger _logger;
  final VendorPayloadAdapterRegistry _adapters;
  static const _parser = ChatChunkParser();

  @override
  /// 发送流式请求并把 SSE 事件转换为内容与推理增量。
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async* {
    final uri = Uri.tryParse(modelConfig.apiUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const ChatCompletionException('API URL 无效，请在设置页检查模型配置。');
    }

    final patch = _adapters.resolve(uri.host).buildPatch(reasoningEffort);
    final payload = <String, Object>{
      'model': modelConfig.modelName,
      'stream': true,
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
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer ${modelConfig.apiKey}',
      })
      ..body = jsonEncode(payload);

    _fireAndForget(
      _logger.logRequest(
        uri: uri,
        method: request.method,
        headers: request.headers,
        payload: payload,
      ),
    );

    final requestStartedAt = DateTime.now();
    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } catch (error, stackTrace) {
      _fireAndForget(
        _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
      );
      rethrow;
    }
    _fireAndForget(
      _logger.logResponse(
        uri: uri,
        statusCode: response.statusCode,
        headers: response.headers,
        elapsed: DateTime.now().difference(requestStartedAt),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      _fireAndForget(
        _logger.logError(
          uri: uri,
          error:
              'HTTP ${response.statusCode}: ${responseBody.trim().isEmpty ? "服务端未返回错误详情" : responseBody.trim()}',
        ),
      );
      throw ChatCompletionException(
        '请求失败（${response.statusCode}）：${responseBody.trim().isEmpty ? "服务端未返回错误详情" : responseBody.trim()}',
      );
    }

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
            _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
          );
          rethrow;
        }
        continue;
      }

      if (line.startsWith('data:')) {
        final dataLine = line.substring(5).trimLeft();
        dataLines.add(dataLine);
        _fireAndForget(_logger.logSseLine(uri: uri, line: dataLine));
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
          _logger.logError(uri: uri, error: error, stackTrace: stackTrace),
        );
        rethrow;
      }
    }

    final trailingInlineReasoning = inlineReasoningSplitter.flushRemainder();
    if (trailingInlineReasoning != null && !trailingInlineReasoning.isEmpty) {
      yield trailingInlineReasoning;
    }
  }

  static const _doneMarker = '[DONE]';

  void _fireAndForget(Future<void> future) {
    unawaited(future);
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
}