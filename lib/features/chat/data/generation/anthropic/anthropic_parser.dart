import 'dart:convert';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

import '../../../application/ports/chat_generation_client.dart';
import '../../../domain/models/chat_generation_usage.dart';

/// 单个 Anthropic SSE 事件的解析结果。
///
/// [chunk] 非空时由客户端 yield；[isDone] 为 true 表示到达 `message_stop`
/// 结束标记，客户端应立即停止消费；[recognized] 为 false 表示无法识别的
/// 新事件类型，客户端记录脱敏诊断后忽略。
typedef AnthropicParseResult = ({
  ChatGenerationChunk? chunk,
  bool isDone,
  bool recognized,
});

/// 解析 Anthropic Messages 协议 SSE 事件（[SseEvent.data] -> [ChatGenerationChunk]）。
///
/// 按事件 `type` 字段分发：
/// - `content_block_delta` + `delta.type=text_delta`：`delta.text` 进入
///   contentDelta。
/// - `content_block_delta` + `delta.type=thinking_delta`：`delta.thinking`
///   进入 reasoningDelta。
/// - `content_block_delta` + `delta.type=signature_delta`：忽略。
/// - `message_start.message.usage`：提取输入与缓存用量。
/// - `message_delta.delta.stop_reason`：归一化后作为 finishReason；自然携带的
///   输出用量与此前用量合并。
/// - `message_stop`：正常结束标记。
/// - `ping`、`content_block_start` / `content_block_stop`：已知生命周期事件，
///   忽略。
/// - `error`：从官方错误 envelope（`error.type`/`error.message`）提取
///   code/message 后抛 [ChatGenerationException]。
/// - 工具内容块（`tool_use` / `server_tool_use` / `input_json_delta`）：
///   普通聊天不发送 tools，收到即抛「不支持该响应类型」异常。
/// - 无法识别的新事件类型：按未知事件忽略；事件名明确声明 tool、error、
///   failed 或 incomplete 时不得忽略。
///
/// 每次请求创建一个 parser 实例，不跨请求复用。
class AnthropicParser {
  AnthropicParser({required this._protocol, required this._uri});

  final LlmApiProtocol _protocol;
  final Uri _uri;
  ChatGenerationUsage? _usage;

  /// 解析一个 SSE 事件。
  AnthropicParseResult parse(SseEvent event) {
    // 事件 data 由 decoder 保证边界；两端空白不影响 JSON 解析。
    final data = event.data.trim();

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
      // 非对象 JSON（如数组）没有协议字段，按未知事件忽略。
      return (chunk: null, isDone: false, recognized: false);
    }

    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      // 无 type 字段的事件按未知事件忽略。
      return (chunk: null, isDone: false, recognized: false);
    }

    switch (type) {
      case 'content_block_delta':
        return _handleContentBlockDelta(decoded, data);
      case 'message_delta':
        return _handleMessageDelta(decoded);
      case 'message_start':
        return _handleMessageStart(decoded);
      case 'message_stop':
        return (chunk: null, isDone: true, recognized: true);
      case 'content_block_start':
        return _handleContentBlockStart(decoded, data);
      case 'error':
        return _throwErrorEvent(decoded, data);
      case 'ping':
      case 'content_block_stop':
        // 已知生命周期/记账事件：与文本无关，忽略。
        return (chunk: null, isDone: false, recognized: true);
      default:
        // 事件明确声明工具、错误或失败语义时不得按未知事件忽略；按 `_`
        // 分词后与关键字精确匹配，避免 tooltip_ready 这类前缀近似误伤。
        if (type
            .toLowerCase()
            .split('_')
            .any(
              (token) =>
                  token == 'tool' ||
                  token == 'error' ||
                  token == 'failed' ||
                  token == 'incomplete',
            )) {
          throw ChatGenerationException(
            '不支持该响应类型：$type',
            protocol: _protocol,
            uri: _uri,
            responseBody: data,
          );
        }
        // 无法识别的新事件类型：记录脱敏诊断后忽略。
        return (chunk: null, isDone: false, recognized: false);
    }
  }

  /// `message_start`：从原生 message envelope 提取输入与缓存用量。
  AnthropicParseResult _handleMessageStart(Map decoded) {
    final message = decoded['message'];
    final eventUsage = message is Map ? _extractUsage(message['usage']) : null;
    if (eventUsage == null) {
      return (chunk: null, isDone: false, recognized: true);
    }
    _usage = _usage?.merge(eventUsage) ?? eventUsage;
    return (
      chunk: ChatGenerationChunk(usage: _usage),
      isDone: false,
      recognized: true,
    );
  }

  /// `content_block_start`：只接受普通文本与思考块，其余内容类型明确失败。
  AnthropicParseResult _handleContentBlockStart(Map decoded, String data) {
    final block = decoded['content_block'];
    final blockType = block is Map ? block['type'] : null;
    if (blockType == 'text' ||
        blockType == 'thinking' ||
        blockType == 'redacted_thinking') {
      return (chunk: null, isDone: false, recognized: true);
    }
    throw ChatGenerationException(
      '不支持该响应类型：收到 ${blockType ?? 'unknown'} 内容块（普通聊天不发送 tools）',
      protocol: _protocol,
      uri: _uri,
      responseBody: data,
    );
  }

  /// `content_block_delta`：按 delta 类型分发文本增量与推理增量。
  AnthropicParseResult _handleContentBlockDelta(Map decoded, String data) {
    final delta = decoded['delta'];
    if (delta is! Map) {
      // 无 delta 的记账事件，忽略。
      return (chunk: null, isDone: false, recognized: true);
    }
    final deltaType = delta['type'];
    switch (deltaType) {
      case 'text_delta':
        final text = delta['text'];
        return _textResult(contentDelta: text is String ? text : '');
      case 'thinking_delta':
        final thinking = delta['thinking'];
        return _textResult(reasoningDelta: thinking is String ? thinking : '');
      case 'signature_delta':
        // 签名与文本无关，忽略。
        return (chunk: null, isDone: false, recognized: true);
      case 'input_json_delta':
        // 工具入参增量只出现在 tool_use 流中，普通聊天不支持。
        throw ChatGenerationException(
          '不支持该响应类型：收到 input_json_delta 内容块（普通聊天不发送 tools）',
          protocol: _protocol,
          uri: _uri,
          responseBody: data,
        );
      default:
        // 未知 delta 类型：记录脱敏诊断后忽略。
        return (chunk: null, isDone: false, recognized: false);
    }
  }

  /// `message_delta`：提取归一化 stop_reason 与自然携带的 usage。
  AnthropicParseResult _handleMessageDelta(Map decoded) {
    final delta = decoded['delta'];
    final rawStopReason = delta is Map ? delta['stop_reason'] : null;
    final eventUsage = _extractUsage(decoded['usage']);
    if (eventUsage != null) {
      _usage = _usage?.merge(eventUsage) ?? eventUsage;
    }

    final stopReason = rawStopReason is String ? rawStopReason : null;
    if (stopReason == null && eventUsage == null) {
      // 无 stop_reason 也无 usage 的记账事件，忽略。
      return (chunk: null, isDone: false, recognized: true);
    }
    return (
      chunk: ChatGenerationChunk(
        finishReason: stopReason == null
            ? null
            : _normalizeFinishReason(stopReason),
        usage: eventUsage == null ? null : _usage,
      ),
      isDone: false,
      recognized: true,
    );
  }

  /// 文本增量事件的结果。
  AnthropicParseResult _textResult({
    String contentDelta = '',
    String reasoningDelta = '',
  }) {
    return (
      chunk: ChatGenerationChunk(
        contentDelta: contentDelta,
        reasoningDelta: reasoningDelta,
      ),
      isDone: false,
      recognized: true,
    );
  }

  /// `error` 事件：从官方错误 envelope（`error.type`/`error.message`）提取
  /// code/message 后抛异常。
  Never _throwErrorEvent(Map decoded, String data) {
    final error = decoded['error'];
    final message = error is Map ? error['message'] : null;
    final code = error is Map ? error['type'] : null;
    throw ChatGenerationException(
      message is String && message.trim().isNotEmpty
          ? message.trim()
          : '服务端返回 error 事件',
      protocol: _protocol,
      uri: _uri,
      apiErrorCode: code is String && code.trim().isNotEmpty
          ? code.trim()
          : null,
      responseBody: data,
    );
  }

  /// Anthropic 原始 finish reason 归一化：
  /// `end_turn` / `stop_sequence` -> stop；`max_tokens` /
  /// `model_context_window_exceeded` -> length；`refusal` -> refusal；其余保留。
  String _normalizeFinishReason(String raw) {
    return switch (raw) {
      'end_turn' || 'stop_sequence' => 'stop',
      'max_tokens' || 'model_context_window_exceeded' => 'length',
      'refusal' => 'refusal',
      _ => raw,
    };
  }

  /// 从协议 `usage` 对象提取用量；缺失或非 int 的字段保持 null。
  ///
  /// Anthropic 的 input_tokens 不含缓存读写，因此展示用的输入总数需求和。
  ChatGenerationUsage? _extractUsage(Object? usage) {
    if (usage is! Map) return null;

    final rawInputTokens = _nonNegativeIntOrNull(usage['input_tokens']);
    final cachedInputTokens = _nonNegativeIntOrNull(
      usage['cache_read_input_tokens'],
    );
    final cacheWriteInputTokens = _nonNegativeIntOrNull(
      usage['cache_creation_input_tokens'],
    );
    final extracted = ChatGenerationUsage(
      inputTokens: rawInputTokens == null
          ? null
          : rawInputTokens +
                (cachedInputTokens ?? 0) +
                (cacheWriteInputTokens ?? 0),
      outputTokens: _nonNegativeIntOrNull(usage['output_tokens']),
      cachedInputTokens: cachedInputTokens,
      cacheWriteInputTokens: cacheWriteInputTokens,
    );
    return extracted.hasAnyValue ? extracted : null;
  }

  int? _nonNegativeIntOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }
}
