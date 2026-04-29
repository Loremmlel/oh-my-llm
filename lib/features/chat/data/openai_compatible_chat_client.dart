import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_network_logger_provider.dart';
import '../../../core/logging/network_logger.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../domain/models/chat_message.dart';
import 'chat_completion_client.dart';

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
  }) : _httpClient = httpClient,
       _logger = logger;

  final http.Client _httpClient;
  final NetworkLogger _logger;

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
    final thinkingConfig = _buildThinkingConfig(
      uri,
      enabled: reasoningEffort != null,
    );
    // DeepSeek 主机需要 thinking 字段；reasoning_effort 无论如何都不做映射。
    final payload = <String, Object>{
      'model': modelConfig.modelName,
      'stream': true,
      'messages': messages.map((message) => message.toJson()).toList(),
      if (reasoningEffort != null)
        'reasoning_effort': _buildReasoningEffort(uri, reasoningEffort),
    };
    if (thinkingConfig != null) {
      payload['thinking'] = thinkingConfig;
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
              'HTTP ${response.statusCode}: ${responseBody.trim().isEmpty ? '服务端未返回错误详情' : responseBody.trim()}',
        ),
      );
      throw ChatCompletionException(
        '请求失败（${response.statusCode}）：${responseBody.trim().isEmpty ? '服务端未返回错误详情' : responseBody.trim()}',
      );
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final dataLines = <String>[];
    final inlineReasoningSplitter = _InlineReasoningTagSplitter();

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
          yield _parseChunk(
            chunk,
            inlineReasoningSplitter: inlineReasoningSplitter,
          );
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
        yield _parseChunk(
          trailingChunk,
          inlineReasoningSplitter: inlineReasoningSplitter,
        );
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

  /// 解析单个 SSE data 块，兼容错误结构和补全文本结构。
  ChatCompletionChunk _parseChunk(
    String rawChunk, {
    required _InlineReasoningTagSplitter inlineReasoningSplitter,
  }) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(rawChunk);
    } on FormatException {
      throw const ChatCompletionException('服务端返回了无法解析的流式数据。');
    }

    if (decoded is! Map) {
      return const ChatCompletionChunk();
    }

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ChatCompletionException(error.trim());
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw ChatCompletionException(message.trim());
      }
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const ChatCompletionChunk();
    }

    final firstChoice = Map<String, dynamic>.from(choices.first as Map);
    final delta = firstChoice['delta'] ?? firstChoice['message'];
    return _extractChunk(
      delta,
      inlineReasoningSplitter: inlineReasoningSplitter,
    );
  }

  /// 从 delta/message 载荷中提取正文和推理文本。
  ChatCompletionChunk _extractChunk(
    Object? payload, {
    required _InlineReasoningTagSplitter inlineReasoningSplitter,
  }) {
    if (payload is String) {
      final splitResult = inlineReasoningSplitter.splitContent(payload);
      return ChatCompletionChunk(
        contentDelta: splitResult.content,
        reasoningDelta: splitResult.reasoning,
      );
    }
    if (payload is! Map) {
      return const ChatCompletionChunk();
    }

    final extractedContent = _extractContentPayload(payload['content']);
    final splitResult = inlineReasoningSplitter.splitContent(
      extractedContent.content,
    );
    final explicitReasoning = _extractTextPayload(
      payload['reasoning_content'] ?? payload['reasoning'],
    );

    return ChatCompletionChunk(
      contentDelta: splitResult.content,
      reasoningDelta:
          '$explicitReasoning${extractedContent.reasoning}${splitResult.reasoning}',
    );
  }

  /// 提取 content 字段中的正文与思考摘要（part.thought=true）。
  _ChunkTextExtraction _extractContentPayload(
    Object? payload, {
    bool forceReasoning = false,
  }) {
    if (payload is String) {
      return forceReasoning
          ? _ChunkTextExtraction(reasoning: payload)
          : _ChunkTextExtraction(content: payload);
    }
    if (payload is List) {
      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      for (final segment in payload) {
        final extracted = _extractContentPayload(
          segment,
          forceReasoning: forceReasoning,
        );
        contentBuffer.write(extracted.content);
        reasoningBuffer.write(extracted.reasoning);
      }
      return _ChunkTextExtraction(
        content: contentBuffer.toString(),
        reasoning: reasoningBuffer.toString(),
      );
    }
    if (payload is! Map) {
      return const _ChunkTextExtraction();
    }

    final thoughtEnabled = _isThoughtPart(payload['thought']);
    final nextForceReasoning = forceReasoning || thoughtEnabled;
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();

    final text = payload['text'];
    if (text is String) {
      if (nextForceReasoning) {
        reasoningBuffer.write(text);
      } else {
        contentBuffer.write(text);
      }
    }

    final nestedContent = _extractContentPayload(
      payload['content'],
      forceReasoning: nextForceReasoning,
    );
    contentBuffer.write(nestedContent.content);
    reasoningBuffer.write(nestedContent.reasoning);

    final nestedParts = _extractContentPayload(
      payload['parts'],
      forceReasoning: nextForceReasoning,
    );
    contentBuffer.write(nestedParts.content);
    reasoningBuffer.write(nestedParts.reasoning);

    return _ChunkTextExtraction(
      content: contentBuffer.toString(),
      reasoning: reasoningBuffer.toString(),
    );
  }

  bool _isThoughtPart(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  /// 兼容字符串、数组和嵌套对象形式的文本字段。
  String _extractTextPayload(Object? payload) {
    if (payload is String) {
      return payload;
    }
    if (payload is List) {
      return payload.map(_extractSegmentText).join();
    }
    if (payload is! Map) {
      return '';
    }

    final text = payload['text'];
    if (text is String) {
      return text;
    }

    final nestedText = payload['content'];
    if (nestedText is String) {
      return nestedText;
    }
    if (nestedText is List) {
      return nestedText.map(_extractSegmentText).join();
    }

    return '';
  }

  /// 兼容多段 segment 结构中的文本字段。
  String _extractSegmentText(Object? segment) {
    if (segment is String) {
      return segment;
    }
    if (segment is! Map) {
      return '';
    }

    final text = segment['text'];
    if (text is String) {
      return text;
    }

    final nestedText = segment['content'];
    if (nestedText is String) {
      return nestedText;
    }
    if (nestedText is List) {
      return nestedText.map(_extractSegmentText).join();
    }

    return '';
  }

  /// DeepSeek 主机需要显式携带 thinking 开关。
  Map<String, String>? _buildThinkingConfig(Uri uri, {required bool enabled}) {
    if (!_isDeepSeekHost(uri.host)) {
      return null;
    }

    return {'type': enabled ? 'enabled' : 'disabled'};
  }

  /// 不做 reasoning effort 映射，直接使用用户设置的值；让 API 厂商处理兼容性。
  String _buildReasoningEffort(Uri uri, ReasoningEffort effort) {
    return effort.apiValue;
  }

  /// 判断是否为 DeepSeek 主机。
  bool _isDeepSeekHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'api.deepseek.com';
  }
}

class _InlineReasoningSplitResult {
  const _InlineReasoningSplitResult({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;

  bool get isEmpty => content.isEmpty && reasoning.isEmpty;
}

class _ChunkTextExtraction {
  const _ChunkTextExtraction({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;
}

/// 从正文中抽取 thought/thinking 标签内容，转入 reasoning。
class _InlineReasoningTagSplitter {
  static final RegExp _openingTag = RegExp(
    r'^<\s*(thoughts?|thinkings?)\b[^>]*>$',
    caseSensitive: false,
  );
  static final RegExp _closingTag = RegExp(
    r'^<\s*/\s*(thoughts?|thinkings?)\s*>$',
    caseSensitive: false,
  );

  bool _insideReasoningTag = false;
  String _tail = '';

  _InlineReasoningSplitResult splitContent(String delta) {
    if (delta.isEmpty && _tail.isEmpty) {
      return const _InlineReasoningSplitResult();
    }

    final input = '$_tail$delta';
    _tail = '';
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    var cursor = 0;

    while (cursor < input.length) {
      final tagStart = input.indexOf('<', cursor);
      if (tagStart == -1) {
        final remaining = input.substring(cursor);
        if (_insideReasoningTag) {
          reasoningBuffer.write(remaining);
        } else {
          contentBuffer.write(remaining);
        }
        break;
      }

      final beforeTag = input.substring(cursor, tagStart);
      if (_insideReasoningTag) {
        reasoningBuffer.write(beforeTag);
      } else {
        contentBuffer.write(beforeTag);
      }

      final tagEnd = input.indexOf('>', tagStart + 1);
      if (tagEnd == -1) {
        _tail = input.substring(tagStart);
        break;
      }

      final candidateTag = input.substring(tagStart, tagEnd + 1);
      if (!_insideReasoningTag && _openingTag.hasMatch(candidateTag)) {
        _insideReasoningTag = true;
        cursor = tagEnd + 1;
        continue;
      }

      if (_insideReasoningTag && _closingTag.hasMatch(candidateTag)) {
        _insideReasoningTag = false;
        cursor = tagEnd + 1;
        continue;
      }

      if (_insideReasoningTag) {
        reasoningBuffer.write('<');
      } else {
        contentBuffer.write('<');
      }
      cursor = tagStart + 1;
    }

    return _InlineReasoningSplitResult(
      content: contentBuffer.toString(),
      reasoning: reasoningBuffer.toString(),
    );
  }

  ChatCompletionChunk? flushRemainder() {
    if (_tail.isEmpty) {
      return null;
    }

    final remainder = _tail;
    _tail = '';
    if (_insideReasoningTag) {
      return ChatCompletionChunk(reasoningDelta: remainder);
    }
    return ChatCompletionChunk(contentDelta: remainder);
  }
}

/// 流式补全请求失败时抛出的业务异常。
class ChatCompletionException implements Exception {
  const ChatCompletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
