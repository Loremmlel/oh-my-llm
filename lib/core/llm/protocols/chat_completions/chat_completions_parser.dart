import 'dart:convert';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../../llm_content.dart';

/// 单个 Chat Completions SSE 事件的解析结果。
///
/// [chunk] 非空时由客户端 yield；[isDone] 为 true 表示正常流结束（`[DONE]`），
/// 客户端应立即停止消费。本协议不存在未知事件概念，所有事件都有明确语义。
typedef ChatCompletionsParseResult = ({LlmEvent? chunk, bool isDone});

/// 解析 Chat Completions 协议 SSE 事件（[SseEvent.data] -> [LlmEvent]）。
///
/// 规则：
/// - `choices[0].delta.content`（String）原样进入 contentDelta。
/// - `choices[0].delta.reasoning_content` 原样进入 reasoningDelta。
/// - `choices[0].finish_reason` 原样透传，不归一化。
/// - `[DONE]` 表示正常流结束；`choices[0].message` 作为 `delta` 的兼容 envelope。
/// - 不再接收 `reasoning` 作为 `reasoning_content` 别名；`delta.content` 为
///   List 等非 String 形状时按无内容处理，不提取文本。
/// - SSE 内 `error`（String 或 Map.message）抛 [LlmException]。
///
/// 每次请求创建一个 parser 实例，参数缓冲不跨请求复用。
class ChatCompletionsParser {
  ChatCompletionsParser({required this._protocol, required this._uri});
  final LlmApiProtocol _protocol;
  final Uri _uri;
  final _tools = <int, _ToolBuffer>{};
  final _deltas = <LlmToolArgumentsDelta>[];
  String? _finishReason;

  List<LlmToolArgumentsDelta> takeToolDeltas() {
    final result = _deltas.toList();
    _deltas.clear();
    return result;
  }

  List<LlmToolCall> finishToolCalls() {
    if (_tools.isEmpty) {
      if (_finishReason == 'tool_calls') throw const LlmException('工具终态缺少调用');
      return [];
    }
    if (_finishReason != 'tool_calls') throw const LlmException('工具调用未完整结束');
    final indexes = _tools.keys.toList()..sort();
    return [
      for (final index in indexes)
        LlmToolCall(
          callId: _tools[index]!.id.toString(),
          name: _tools[index]!.name.toString(),
          argumentsJson: _tools[index]!.arguments.toString(),
        ),
    ];
  }

  void _readTools(Object? envelope, {required bool completeMessage}) {
    if (envelope is! Map || envelope['tool_calls'] == null) return;
    final calls = envelope['tool_calls'];
    if (calls is! List) throw const LlmException('tool_calls 必须为数组');
    for (var position = 0; position < calls.length; position++) {
      final call = calls[position];
      if (call is! Map) throw const LlmException('工具调用必须为对象');
      final index = call['index'] ?? (completeMessage ? position : null);
      if (index is! int ||
          index < 0 ||
          (call['type'] != null && call['type'] != 'function')) {
        throw const LlmException('工具调用索引或类型无效');
      }
      if (!_tools.containsKey(index) && _tools.length >= maxLlmToolCalls) {
        throw const LlmException('工具调用数量超过限制');
      }
      final buffer = _tools.putIfAbsent(index, _ToolBuffer.new);
      final function = call['function'];
      if (function != null && function is! Map) {
        throw const LlmException('工具 function 必须为对象');
      }
      final id = call['id'];
      final name = function is Map ? function['name'] : null;
      final args = function is Map ? function['arguments'] : null;
      for (final value in [id, name, args]) {
        if (value != null && value is! String) {
          throw const LlmException('工具参数片段必须为字符串');
        }
      }
      final fragment = args as String? ?? '';
      buffer.bytes +=
          utf8.encode(fragment).length +
          utf8.encode(id as String? ?? '').length +
          utf8.encode(name as String? ?? '').length;
      if (buffer.bytes > maxLlmToolBytes) {
        throw const LlmException('工具参数超过大小限制');
      }
      buffer.id.write(id ?? '');
      buffer.name.write(name ?? '');
      buffer.arguments.write(fragment);
      _deltas.add(
        LlmToolArgumentsDelta(
          index: index,
          callId: id,
          name: name,
          argumentsDelta: fragment,
        ),
      );
    }
  }

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
      throw LlmException(
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
      throw LlmException(
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
        throw LlmException(
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

    final usage = _extractUsage(decoded['usage']);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return (
        chunk: usage == null ? null : LlmEvent(usage: usage),
        isDone: false,
      );
    }

    final firstChoice = Map<String, dynamic>.from(choices.first as Map);
    final rawFinishReason = firstChoice['finish_reason'];
    final finishReason = rawFinishReason is String ? rawFinishReason : null;
    _finishReason = finishReason ?? _finishReason;
    final envelope = firstChoice['delta'] ?? firstChoice['message'];
    _readTools(envelope, completeMessage: firstChoice['delta'] == null);
    final chunk = _extractChunk(envelope, finishReason: finishReason);
    return (
      chunk: usage == null
          ? chunk
          : LlmEvent(
              contentDelta: chunk.contentDelta,
              reasoningDelta: chunk.reasoningDelta,
              finishReason: chunk.finishReason,
              usage: usage,
            ),
      isDone: false,
    );
  }

  LlmEvent _extractChunk(Object? envelope, {String? finishReason}) {
    if (envelope is! Map) {
      return LlmEvent(finishReason: finishReason);
    }
    final delta = Map<String, dynamic>.from(envelope);

    final content = delta['content'];
    final reasoningBuffer = StringBuffer();
    final explicitReasoning = delta['reasoning_content'];
    if (explicitReasoning is String) {
      reasoningBuffer.write(explicitReasoning);
    }

    return LlmEvent(
      contentDelta: content is String ? content : '',
      reasoningDelta: reasoningBuffer.toString(),
      finishReason: finishReason,
    );
  }

  /// 从顶层 `usage` 提取用量；缺失或非 int 的字段保持 null。
  LlmUsage? _extractUsage(Object? usage) {
    if (usage is! Map) return null;

    final completionDetails = usage['completion_tokens_details'];
    final promptDetails = usage['prompt_tokens_details'];
    final extracted = LlmUsage(
      inputTokens: _intOrNull(usage['prompt_tokens']),
      outputTokens: _intOrNull(usage['completion_tokens']),
      reasoningTokens: completionDetails is Map
          ? _intOrNull(completionDetails['reasoning_tokens'])
          : null,
      cachedInputTokens: promptDetails is Map
          ? _intOrNull(promptDetails['cached_tokens'])
          : null,
      cacheWriteInputTokens: promptDetails is Map
          ? _intOrNull(promptDetails['cache_write_tokens'])
          : null,
    );
    return extracted.hasAnyValue ? extracted : null;
  }

  int? _intOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }
}

class _ToolBuffer {
  final id = StringBuffer();
  final name = StringBuffer();
  final arguments = StringBuffer();
  int bytes = 0;
}
