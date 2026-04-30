import 'dart:convert';

import 'chat_completion_client.dart';

/// SSE data 块的解析结果，包含从正文和 delta 中提取出的正文与推理文本。
class ChunkTextExtraction {
  const ChunkTextExtraction({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;
}

/// 内联 reasoning 标签分割结果。
class InlineReasoningSplitResult {
  const InlineReasoningSplitResult({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;

  bool get isEmpty => content.isEmpty && reasoning.isEmpty;
}

/// 从正文流中识别并分离 `<thought>`/`<thinking>` 标签内容，转入 reasoning 通道。
///
/// 用于 Gemma-IT 等以 `<thought>…</thought>` 方式内嵌思考过程的模型。
/// 每个请求创建一个新实例，以保持跨 chunk 的标签解析状态。
class InlineReasoningTagSplitter {
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

  InlineReasoningSplitResult splitContent(String delta) {
    if (delta.isEmpty && _tail.isEmpty) {
      return const InlineReasoningSplitResult();
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

    return InlineReasoningSplitResult(
      content: contentBuffer.toString(),
      reasoning: reasoningBuffer.toString(),
    );
  }

  /// 刷新缓冲区中残留的不完整标签内容。
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

/// 从单个 SSE delta/message payload 提取正文与推理增量。
///
/// 兼容以下厂商的返回格式：
/// - 标准 OpenAI：`delta.content` 为字符串
/// - DeepSeek：`delta.reasoning_content` 或 `delta.reasoning`
/// - Gemini parts：`delta.content` 为含 `{text, thought}` 的列表
/// - Gemma-IT 内联标签：由 [InlineReasoningTagSplitter] 处理
class ChatChunkParser {
  const ChatChunkParser();

  /// 解析完整的 SSE data 块（JSON 字符串），返回补全增量。
  ///
  /// 若为 `[DONE]` 或格式异常，返回 `null`。
  ChatCompletionChunk? parseRawChunk(
    String rawChunk, {
    required InlineReasoningTagSplitter inlineReasoningSplitter,
  }) {
    if (rawChunk == '[DONE]') {
      return null;
    }

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
    return _extractChunk(delta, inlineReasoningSplitter: inlineReasoningSplitter);
  }

  ChatCompletionChunk _extractChunk(
    Object? payload, {
    required InlineReasoningTagSplitter inlineReasoningSplitter,
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
  ChunkTextExtraction _extractContentPayload(
    Object? payload, {
    bool forceReasoning = false,
  }) {
    if (payload is String) {
      return forceReasoning
          ? ChunkTextExtraction(reasoning: payload)
          : ChunkTextExtraction(content: payload);
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
      return ChunkTextExtraction(
        content: contentBuffer.toString(),
        reasoning: reasoningBuffer.toString(),
      );
    }
    if (payload is! Map) {
      return const ChunkTextExtraction();
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

    return ChunkTextExtraction(
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
}
