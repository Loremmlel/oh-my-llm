import 'dart:convert';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

import '../../../application/ports/chat_generation_client.dart';
import 'inline_reasoning_tag_splitter.dart';

/// 单个 Chat Completions SSE 事件的解析结果。
///
/// [chunk] 非空时由客户端 yield；[isDone] 为 true 表示正常流结束（`[DONE]`），
/// 客户端应立即停止消费。本协议不存在未知事件概念，所有事件都有明确语义。
typedef ChatCompletionsParseResult = ({
  ChatGenerationChunk? chunk,
  bool isDone,
});

/// 解析 Chat Completions 协议 SSE 事件（[SseEvent.data] -> [ChatGenerationChunk]）。
///
/// 规则：
/// - `choices[0].delta.content`（String）经内联标签 splitter 进入 contentDelta。
/// - `choices[0].delta.reasoning_content` 先追加，再追加从 content 提取的内联 reasoning。
/// - `choices[0].finish_reason` 原样透传，不归一化。
/// - `[DONE]` 表示正常流结束；`choices[0].message` 作为 `delta` 的兼容 envelope。
/// - 不再接收 `reasoning` 作为 `reasoning_content` 别名；`delta.content` 为
///   List 等非 String 形状时按无内容处理，不提取文本。
/// - SSE 内 `error`（String 或 Map.message）抛 [ChatGenerationException]。
///
/// 每次请求创建一个 parser 实例，splitter 状态不跨请求复用。
class ChatCompletionsParser {
  ChatCompletionsParser({
    required LlmApiProtocol protocol,
    required Uri uri,
    InlineReasoningTagSplitter? inlineReasoningSplitter,
  }) : _protocol = protocol,
       _uri = uri,
       _inlineReasoningSplitter =
           inlineReasoningSplitter ?? InlineReasoningTagSplitter();

  final LlmApiProtocol _protocol;
  final Uri _uri;
  final InlineReasoningTagSplitter _inlineReasoningSplitter;

  /// 解析一个 SSE 事件。
  ChatCompletionsParseResult parse(SseEvent event) {
    // 事件 data 由 decoder 保证边界；两端空白不影响 JSON 解析。
    final data = event.data.trim();
    if (data == '[DONE]') {
      return (chunk: null, isDone: true);
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      throw ChatGenerationException(
        'SSE 数据解析失败：${data.length > 100 ? '${data.substring(0, 100)}…' : data}',
        protocol: _protocol,
        uri: _uri,
        responseBody: data,
      );
    }

    if (decoded is! Map) {
      // 非对象 JSON（如数组）没有协议字段，按空事件忽略。
      return (chunk: null, isDone: false);
    }

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ChatGenerationException(
        error.trim(),
        protocol: _protocol,
        uri: _uri,
        responseBody: data,
      );
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        final code = error['code'];
        throw ChatGenerationException(
          message.trim(),
          protocol: _protocol,
          uri: _uri,
          apiErrorCode: code is String && code.trim().isNotEmpty
              ? code.trim()
              : null,
          responseBody: data,
        );
      }
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return (chunk: null, isDone: false);
    }

    final firstChoice = Map<String, dynamic>.from(choices.first as Map);
    final rawFinishReason = firstChoice['finish_reason'];
    final finishReason = rawFinishReason is String ? rawFinishReason : null;
    final usage = _extractUsage(decoded['usage']);

    final envelope = firstChoice['delta'] ?? firstChoice['message'];
    final chunk = _extractChunk(envelope, finishReason: finishReason);
    return (
      chunk: usage == null
          ? chunk
          : ChatGenerationChunk(
              contentDelta: chunk.contentDelta,
              reasoningDelta: chunk.reasoningDelta,
              finishReason: chunk.finishReason,
              usage: usage,
            ),
      isDone: false,
    );
  }

  /// 流结束时刷新 splitter 尾部残留（不完整标签按当前通道输出）。
  ChatGenerationChunk? finish() {
    return _inlineReasoningSplitter.flushRemainder();
  }

  ChatGenerationChunk _extractChunk(Object? envelope, {String? finishReason}) {
    if (envelope is! Map) {
      return ChatGenerationChunk(finishReason: finishReason);
    }
    final delta = Map<String, dynamic>.from(envelope);

    final content = delta['content'];
    // List parts 与其余非 String 形状按无内容处理；splitter 仍需处理残留尾部。
    final splitResult = _inlineReasoningSplitter.splitContent(
      content is String ? content : '',
    );

    final reasoningBuffer = StringBuffer();
    final explicitReasoning = delta['reasoning_content'];
    if (explicitReasoning is String) {
      reasoningBuffer.write(explicitReasoning);
    }
    reasoningBuffer.write(splitResult.reasoning);

    return ChatGenerationChunk(
      contentDelta: splitResult.content,
      reasoningDelta: reasoningBuffer.toString(),
      finishReason: finishReason,
    );
  }

  /// 从顶层 `usage` 提取用量；缺失或非 int 的字段保持 null。
  ChatGenerationUsage? _extractUsage(Object? usage) {
    if (usage is! Map) return null;

    final completionDetails = usage['completion_tokens_details'];
    final promptDetails = usage['prompt_tokens_details'];
    final extracted = ChatGenerationUsage(
      inputTokens: _intOrNull(usage['prompt_tokens']),
      outputTokens: _intOrNull(usage['completion_tokens']),
      reasoningTokens: completionDetails is Map
          ? _intOrNull(completionDetails['reasoning_tokens'])
          : null,
      cachedInputTokens: promptDetails is Map
          ? _intOrNull(promptDetails['cached_tokens'])
          : null,
    );
    // 全字段缺失时不冒充已知值，视为未提供 usage。
    if (extracted.inputTokens == null &&
        extracted.outputTokens == null &&
        extracted.reasoningTokens == null &&
        extracted.cachedInputTokens == null) {
      return null;
    }
    return extracted;
  }

  int? _intOrNull(Object? value) => value is int ? value : null;
}
