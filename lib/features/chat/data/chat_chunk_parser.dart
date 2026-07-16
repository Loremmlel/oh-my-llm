import 'dart:convert';

import 'chat_completion_client.dart';
import 'chunk_parse_strategy.dart';

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
    if (_tail.isEmpty) return null;

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
/// 通过 [ChunkParseStrategy] 策略链兼容以下厂商格式：
/// - 标准 OpenAI：`delta.content` 为字符串
/// - DeepSeek：`delta.reasoning_content` 或 `delta.reasoning`
/// - Gemini parts：`delta.content` 为含 `{text, thought}` 的列表
/// - Gemma-IT 内联标签：由 [InlineReasoningTagSplitter] 处理
///
/// 传入自定义 [strategies] 可扩展支持新的厂商格式，默认开启全部内置策略。
class ChatChunkParser {
  static const _defaultStrategies = [
    GeminiPartsChunkStrategy(),
    DeepSeekChunkStrategy(),
    StandardOpenAiChunkStrategy(),
  ];

  const ChatChunkParser({this.strategies = _defaultStrategies});

  final List<ChunkParseStrategy> strategies;

  /// 解析完整的 SSE data 块（JSON 字符串），返回补全增量。
  ///
  /// 若为 `[DONE]` 或格式异常，返回 `null`。
  ChatCompletionChunk? parseRawChunk(
    String rawChunk, {
    required InlineReasoningTagSplitter inlineReasoningSplitter,
  }) {
    if (rawChunk == '[DONE]') return null;

    late final Object? decoded;
    try {
      decoded = jsonDecode(rawChunk);
    } on FormatException {
      throw ChatCompletionException(
        'SSE 数据解析失败',
        responseBody: rawChunk,
      );
    }

    if (decoded is! Map) return const ChatCompletionChunk();

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ChatCompletionException(error.trim(), responseBody: rawChunk);
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw ChatCompletionException(
          message.trim(),
          responseBody: rawChunk,
        );
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
    if (payload is! Map) return const ChatCompletionChunk();

    final delta = Map<String, dynamic>.from(payload);
    ChunkTextExtraction extraction = const ChunkTextExtraction();
    for (final strategy in strategies) {
      if (strategy.canHandle(delta)) {
        extraction = strategy.extract(delta);
        break;
      }
    }

    final splitResult = inlineReasoningSplitter.splitContent(
      extraction.content,
    );

    return ChatCompletionChunk(
      contentDelta: splitResult.content,
      reasoningDelta: '${extraction.reasoning}${splitResult.reasoning}',
    );
  }
}
