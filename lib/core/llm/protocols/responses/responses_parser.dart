import 'dart:convert';

import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../../llm_content.dart';

/// 单个 Responses SSE 事件的解析结果。
///
/// [chunk] 非空时由客户端 yield；[isDone] 为 true 表示流已到达
/// `response.completed` / `response.incomplete` 终态，客户端应立即停止消费；
/// [recognized] 为 false
/// 表示未知且与文本无关的事件，客户端记录诊断后忽略。
typedef ResponsesParseResult = ({
  LlmEvent? chunk,
  bool isDone,
  bool recognized,
});

/// 解析 OpenAI Responses 协议 SSE 事件（[SseEvent.data] -> [LlmEvent]）。
///
/// 按事件 `type` 字段分发：
/// - `response.output_text.delta` 的 `delta` 字段进入 contentDelta。
/// - `response.reasoning_summary_text.delta` / `response.reasoning_text.delta`
///   的 `delta` 字段进入 reasoningDelta。
/// - `response.refusal.delta` 的 `delta` 字段作为用户可见正文进入 contentDelta。
/// - `response.completed` 携带归一化 finishReason（completed -> stop）。
/// - `response.incomplete` 读取 `incomplete_details.reason`（缺失时以
///   `incomplete` 兜底）并归一化。
/// - `response.failed` / `error` 事件提取 message/code 后抛
///   [LlmException]。
/// - `response.done` 只做完整性检查（确认 response envelope 存在），不把
///   其中完整文本追加进流，同时作为流结束标记返回。
/// - usage 取 response envelope 的 `usage` 字段，缺失或非 int 保持 null，
///   全字段缺失视为未提供。
/// - 其余事件类型与文本无关（生命周期/记账/未来新增事件），按未知事件忽略。
///
/// 每次请求创建一个 parser 实例，事件间无跨请求状态。
class ResponsesParser {
  ResponsesParser({required this._protocol, required this._uri});

  final LlmApiProtocol _protocol;
  final Uri _uri;
  final _items = <int, Map<String, Object?>>{};
  final _done = <int>{};
  final _deltas = <LlmToolArgumentsDelta>[];
  bool completed = false;
  bool refused = false;
  bool get hasReliableReplay =>
      completed && _items.isNotEmpty && _items.keys.every(_done.contains);
  String? rawFinishReason;

  List<LlmToolArgumentsDelta> takeToolDeltas() {
    final result = _deltas.toList();
    _deltas.clear();
    return result;
  }

  List<Map<String, Object?>> get nativeItems {
    final indexes = _items.keys.toList()..sort();
    return [for (final index in indexes) _items[index]!];
  }

  String? get completedText {
    if (!hasReliableReplay) return null;
    final text = StringBuffer();
    for (final item in nativeItems) {
      if (item['type'] != 'message' || item['content'] is! List) continue;
      for (final part in item['content'] as List) {
        if (part is Map &&
            part['type'] == 'output_text' &&
            part['text'] is String) {
          text.write(part['text']);
        }
        if (part is Map &&
            part['type'] == 'refusal' &&
            part['refusal'] is String) {
          text.write(part['refusal']);
        }
      }
    }
    return text.toString();
  }

  List<LlmToolCall> finishToolCalls() {
    final calls = <LlmToolCall>[];
    for (final entry in _items.entries) {
      final item = entry.value;
      if (item['type'] != 'function_call') continue;
      if (!completed ||
          !_done.contains(entry.key) ||
          item['status'] == 'incomplete' ||
          item['status'] == 'in_progress') {
        throw const LlmException('Responses 工具调用未完整结束');
      }
      calls.add(
        LlmToolCall(
          callId: item['call_id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          argumentsJson: item['arguments'] as String? ?? '',
        ),
      );
    }
    if (calls.isNotEmpty && !hasReliableReplay) {
      throw const LlmException('工具续接缺少完整原生输出');
    }
    return calls;
  }

  void _storeItem(int index, Object? value, {required bool done}) {
    if (value is! Map || index < 0) {
      throw const LlmException('Responses output item 无效');
    }
    final item = Map<String, Object?>.from(value);
    if (!const [
      'message',
      'reasoning',
      'function_call',
    ].contains(item['type'])) {
      throw LlmException(
        '不支持的 Responses 输出：${item['type']}',
        kind: LlmFailureKind.unsupported,
      );
    }
    final previous = _items[index];
    if (previous != null &&
        (previous['id'] != item['id'] || previous['type'] != item['type'])) {
      throw const LlmException('Responses output index 的 ID 或类型冲突');
    }
    if (item['type'] == 'function_call') {
      if (item['arguments'] is! String) {
        throw const LlmException('工具 arguments 必须为字符串');
      }
      if (utf8.encode(item['arguments'] as String).length > maxLlmToolBytes) {
        throw const LlmException('工具参数超过大小限制');
      }
      final count = _items.entries
          .where((e) => e.key != index && e.value['type'] == 'function_call')
          .length;
      if (count >= maxLlmToolCalls) throw const LlmException('工具调用数量超过限制');
    }
    if (item['type'] == 'message' &&
        item['content'] is List &&
        (item['content'] as List).any(
          (part) => part is Map && part['type'] == 'refusal',
        )) {
      refused = true;
    }
    _items[index] = item;
    if (done) _done.add(index);
  }

  void _recordNative(Map event) {
    final type = event['type'];
    if (type == 'response.refusal.delta') refused = true;
    if (type == 'response.output_item.added' ||
        type == 'response.output_item.done') {
      // 旧文本网关可能只发空的 done 元数据，不能据此推断有可续接 item。
      if (event['item'] == null && event['output_index'] == null) return;
      final index = event['output_index'];
      if (index is! int) throw const LlmException('Responses 缺少 output_index');
      _storeItem(
        index,
        event['item'],
        done: type == 'response.output_item.done',
      );
    } else if (type == 'response.function_call_arguments.delta' ||
        type == 'response.function_call_arguments.done') {
      final index = event['output_index'];
      final item = _items[index];
      if (index is! int ||
          item == null ||
          item['type'] != 'function_call' ||
          item['id'] != event['item_id'] ||
          _done.contains(index)) {
        throw const LlmException('工具参数缺少匹配的 output item');
      }
      final value =
          event[type == 'response.function_call_arguments.delta'
              ? 'delta'
              : 'arguments'];
      if (value is! String) throw const LlmException('工具参数片段必须为字符串');
      final isDelta = type == 'response.function_call_arguments.delta';
      final bytes =
          utf8.encode(value).length +
          (isDelta ? utf8.encode(item['arguments'] as String).length : 0);
      if (bytes > maxLlmToolBytes) throw const LlmException('工具参数超过大小限制');
      final arguments = isDelta ? '${item['arguments']}$value' : value;
      item['arguments'] = arguments;
      if (type == 'response.function_call_arguments.delta') {
        _deltas.add(
          LlmToolArgumentsDelta(
            index: index,
            callId: item['call_id'] as String?,
            name: item['name'] as String?,
            argumentsDelta: value,
          ),
        );
      }
    } else if (type == 'response.completed') {
      completed = true;
      rawFinishReason = 'completed';
      final response = event['response'];
      final output = response is Map ? response['output'] : null;
      if (output is List) {
        if (_items.keys.any((index) => index >= output.length)) {
          throw const LlmException('Responses 终态遗漏已开始的 output item');
        }
        for (var i = 0; i < output.length; i++) {
          _storeItem(i, output[i], done: true);
        }
      }
    } else if (type == 'response.incomplete') {
      rawFinishReason = _incompleteReason(event['response']) ?? 'incomplete';
    }
  }

  /// 解析一个 SSE 事件。
  ResponsesParseResult parse(SseEvent event) {
    // 事件 data 由 decoder 保证边界；两端空白不影响 JSON 解析。
    final data = event.data.trim();

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
      return (chunk: null, isDone: false, recognized: false);
    }

    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      // 无 type 字段的事件按未知事件忽略。
      return (chunk: null, isDone: false, recognized: false);
    }

    _recordNative(decoded);
    switch (type) {
      case 'response.output_text.delta':
      case 'response.refusal.delta':
        final delta = decoded['delta'];
        return _textResult(contentDelta: delta is String ? delta : '');
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final delta = decoded['delta'];
        return _textResult(reasoningDelta: delta is String ? delta : '');
      case 'response.completed':
        return _terminalResult(
          decoded['response'],
          rawFinishReason: 'completed',
        );
      case 'response.incomplete':
        return _terminalResult(
          decoded['response'],
          rawFinishReason:
              _incompleteReason(decoded['response']) ?? 'incomplete',
        );
      case 'response.output_text.done':
      case 'response.reasoning_summary_text.done':
      case 'response.reasoning_text.done':
      case 'response.refusal.done':
      case 'response.content_part.done':
      case 'response.output_item.done':
        // `.done` 携带完整项仅用于协议完整性观察，正文/推理已由 delta 追加，
        // 这里不能重复发出内容。
        return (chunk: null, isDone: false, recognized: true);
      case 'response.failed':
        return _throwFailed(decoded, data);
      case 'error':
        return _throwErrorEvent(decoded, data);
      case 'response.done':
        // 完整性检查：结束标记必须携带 response envelope；其中完整文本
        // 不追加进流（正文已在 delta 事件中增量到达）。
        if (decoded['response'] is! Map) {
          throw LlmException(
            'response.done 事件缺少 response 数据',
            protocol: _protocol,
            uri: _uri,
            responseBody: data,
          );
        }
        return (chunk: null, isDone: true, recognized: true);
      default:
        // 未知事件类型（含生命周期/记账事件）：与文本无关，忽略。
        return (chunk: null, isDone: false, recognized: false);
    }
  }

  /// 文本增量事件的结果。
  ResponsesParseResult _textResult({
    String contentDelta = '',
    String reasoningDelta = '',
  }) {
    return (
      chunk: LlmEvent(
        contentDelta: contentDelta,
        reasoningDelta: reasoningDelta,
      ),
      isDone: false,
      recognized: true,
    );
  }

  /// 终态事件（completed/incomplete）的结果：携带归一化 finishReason 与
  /// response envelope 中自然携带的 usage。
  ResponsesParseResult _terminalResult(
    Object? responseEnvelope, {
    required String rawFinishReason,
  }) {
    final usage = responseEnvelope is Map
        ? _extractUsage(responseEnvelope['usage'])
        : null;
    return (
      chunk: LlmEvent(
        finishReason: _normalizeFinishReason(rawFinishReason),
        usage: usage,
      ),
      isDone: true,
      recognized: true,
    );
  }

  /// 从 response envelope 读取 incomplete 的具体原因；缺失时以事件名兜底。
  String? _incompleteReason(Object? responseEnvelope) {
    if (responseEnvelope is! Map) return null;
    final details = responseEnvelope['incomplete_details'];
    if (details is! Map) return null;
    final reason = details['reason'];
    return reason is String && reason.trim().isNotEmpty ? reason.trim() : null;
  }

  /// `response.failed`：从 `response.error` envelope 提取 message/code 后抛异常。
  Never _throwFailed(Map decoded, String data) {
    final response = decoded['response'];
    final error = response is Map ? response['error'] : null;
    final message = error is Map ? error['message'] : null;
    final code = error is Map ? error['code'] : null;
    throw LlmException(
      message is String && message.trim().isNotEmpty
          ? message.trim()
          : '响应生成失败（服务端未提供错误详情）',
      protocol: _protocol,
      uri: _uri,
      apiErrorCode: code is String && code.trim().isNotEmpty
          ? code.trim()
          : null,
      responseBody: data,
      usage: response is Map ? _extractUsage(response['usage']) : null,
    );
  }

  /// `error` 事件：从事件顶层提取 message/code 后抛异常。
  Never _throwErrorEvent(Map decoded, String data) {
    final message = decoded['message'];
    final code = decoded['code'];
    throw LlmException(
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

  /// Responses 原始 finish reason 归一化：
  /// `completed` -> stop；`incomplete` / `max_output_tokens` -> length；其余保留。
  String _normalizeFinishReason(String raw) {
    return switch (raw) {
      'completed' => 'stop',
      'incomplete' => 'length',
      'max_output_tokens' => 'length',
      _ => raw,
    };
  }

  /// 从 response envelope 的 `usage` 提取用量；缺失或非 int 的字段保持 null。
  LlmUsage? _extractUsage(Object? usage) {
    if (usage is! Map) return null;

    final outputDetails = usage['output_tokens_details'];
    final inputDetails = usage['input_tokens_details'];
    final extracted = LlmUsage(
      inputTokens: _intOrNull(usage['input_tokens']),
      outputTokens: _intOrNull(usage['output_tokens']),
      reasoningTokens: outputDetails is Map
          ? _intOrNull(outputDetails['reasoning_tokens'])
          : null,
      cachedInputTokens: inputDetails is Map
          ? _intOrNull(inputDetails['cached_tokens'])
          : null,
      cacheWriteInputTokens: inputDetails is Map
          ? _intOrNull(inputDetails['cache_write_tokens'])
          : null,
    );
    return extracted.hasAnyValue ? extracted : null;
  }

  int? _intOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }
}
