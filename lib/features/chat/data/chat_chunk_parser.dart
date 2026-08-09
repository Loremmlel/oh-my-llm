import 'dart:convert';

import '../application/ports/chat_generation_client.dart';
import 'chat_completions/inline_reasoning_tag_splitter.dart';
import 'chunk_parse_strategy.dart';

// 内联标签分割器已迁移至 chat_completions/；此处 re-export 保持旧文件
// 使用方的 import 路径不变，旧解析器下线时随本文件一并移除。

export 'chat_completions/inline_reasoning_tag_splitter.dart';

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
  ChatGenerationChunk? parseRawChunk(
    String rawChunk, {
    required InlineReasoningTagSplitter inlineReasoningSplitter,
  }) {
    if (rawChunk == '[DONE]') return null;

    late final Object? decoded;
    try {
      decoded = jsonDecode(rawChunk);
    } on FormatException {
      throw ChatGenerationException(
        'SSE 数据解析失败：${rawChunk.length > 100 ? '${rawChunk.substring(0, 100)}…' : rawChunk}',
        responseBody: rawChunk,
      );
    }

    if (decoded is! Map) return const ChatGenerationChunk();

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ChatGenerationException(error.trim(), responseBody: rawChunk);
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw ChatGenerationException(message.trim(), responseBody: rawChunk);
      }
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const ChatGenerationChunk();
    }

    final firstChoice = Map<String, dynamic>.from(choices.first as Map);
    final delta = firstChoice['delta'] ?? firstChoice['message'];
    final finishReason = firstChoice['finish_reason'] as String?;
    return _extractChunk(
      delta,
      inlineReasoningSplitter: inlineReasoningSplitter,
      finishReason: finishReason,
    );
  }

  ChatGenerationChunk _extractChunk(
    Object? payload, {
    required InlineReasoningTagSplitter inlineReasoningSplitter,
    String? finishReason,
  }) {
    if (payload is String) {
      final splitResult = inlineReasoningSplitter.splitContent(payload);
      return ChatGenerationChunk(
        contentDelta: splitResult.content,
        reasoningDelta: splitResult.reasoning,
        finishReason: finishReason,
      );
    }
    if (payload is! Map) return ChatGenerationChunk(finishReason: finishReason);

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

    return ChatGenerationChunk(
      contentDelta: splitResult.content,
      reasoningDelta: '${extraction.reasoning}${splitResult.reasoning}',
      finishReason: finishReason,
    );
  }
}
