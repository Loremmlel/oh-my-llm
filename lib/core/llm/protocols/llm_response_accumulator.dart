import '../llm_content.dart';
import '../llm_event.dart';
import '../llm_request.dart';
import '../llm_usage.dart';

/// 每个请求独占累积器，增量显示与完整结果共享一次折叠。
class LlmResponseAccumulator {
  final _content = StringBuffer();
  final _reasoning = StringBuffer();
  String? _finishReason;
  LlmUsage? _usage;

  void add(LlmEvent event) {
    _content.write(event.contentDelta);
    _reasoning.write(event.reasoningDelta);
    _finishReason = event.finishReason ?? _finishReason;
    if (event.usage case final update?) {
      _usage = _usage?.merge(update) ?? update;
    }
  }

  LlmResult finish({
    String? diagnosticBody,
    String? completedText,
    LlmRequest? request,
    Uri? endpoint,
    List<Map<String, Object?>>? nativeItems,
    List<LlmToolCall> toolCalls = const [],
    LlmStopKind? stopKind,
    String? rawFinishReason,
    String? requestId,
  }) {
    final names =
        request?.tools.map((tool) => tool.name).toSet() ?? const <String>{};
    final ids = <String>{};
    if (toolCalls.length > maxLlmToolCalls) {
      throw const LlmException('工具调用数量超过限制');
    }
    for (final call in toolCalls) {
      if (!ids.add(call.callId) || !names.contains(call.name)) {
        throw const LlmException('工具调用名称未知或 ID 重复');
      }
    }
    if (toolCalls.isNotEmpty &&
        request != null &&
        (request.toolChoice.kind == LlmToolChoiceKind.none ||
            (request.parallelToolCalls == false && toolCalls.length > 1) ||
            (request.toolChoice.kind == LlmToolChoiceKind.named &&
                toolCalls.any(
                  (call) => call.name != request.toolChoice.name,
                )))) {
      throw const LlmException('返回的工具调用违反请求选择约束');
    }
    return LlmResult(
      requestId: requestId,
      content: completedText ?? _content.toString(),
      reasoningContent: _reasoning.toString(),
      finishReason: rawFinishReason ?? _finishReason,
      usage: _usage,
      diagnosticBody: _content.isEmpty && _reasoning.isEmpty
          ? diagnosticBody
          : null,
      assistantTurn: request == null || endpoint == null || nativeItems == null
          ? null
          : LlmAssistantTurn(
              replay: LlmReplayEnvelope(
                protocol: request.target.protocol,
                endpoint: endpoint,
                model: request.target.model,
                items: nativeItems,
              ),
              text: completedText ?? _content.toString(),
              reasoning: _reasoning.toString(),
              toolCalls: toolCalls,
            ),
      stopKind:
          stopKind ??
          switch (_finishReason) {
            'stop' => LlmStopKind.completed,
            'length' => LlmStopKind.incomplete,
            'refusal' || 'content_filter' => LlmStopKind.refused,
            _ => LlmStopKind.unknown,
          },
    );
  }
}
