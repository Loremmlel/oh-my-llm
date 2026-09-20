import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

/// 调用次数与服务商已报告的用量一起累计，缺失的报告不能被后续成功覆盖。
class AgentRunUsage extends Equatable {
  const AgentRunUsage({
    this.modelCalls = 0,
    this.tokens,
    this.incomplete = false,
  });

  final int modelCalls;
  final LlmUsage? tokens;
  final bool incomplete;

  AgentRunUsage startCall() => AgentRunUsage(
    modelCalls: modelCalls + 1,
    tokens: tokens,
    incomplete: incomplete,
  );

  AgentRunUsage addResponse(LlmUsage? reported) => AgentRunUsage(
    modelCalls: modelCalls,
    tokens: _sumTokens(tokens, reported),
    incomplete:
        incomplete ||
        reported?.inputTokens == null ||
        reported?.outputTokens == null,
  );

  AgentRunUsage add(AgentRunUsage other, {required bool completed}) =>
      AgentRunUsage(
        modelCalls: modelCalls + other.modelCalls,
        tokens: _sumTokens(tokens, other.tokens),
        incomplete: incomplete || other.incomplete || !completed,
      );

  @override
  List<Object?> get props => [modelCalls, tokens, incomplete];
}

LlmUsage? _sumTokens(LlmUsage? a, LlmUsage? b) {
  if (b == null) return a;
  int? sum(int? x, int? y) =>
      x == null && y == null ? null : (x ?? 0) + (y ?? 0);
  return LlmUsage(
    inputTokens: sum(a?.inputTokens, b.inputTokens),
    outputTokens: sum(a?.outputTokens, b.outputTokens),
    reasoningTokens: sum(a?.reasoningTokens, b.reasoningTokens),
    cachedInputTokens: sum(a?.cachedInputTokens, b.cachedInputTokens),
    cacheWriteInputTokens: sum(
      a?.cacheWriteInputTokens,
      b.cacheWriteInputTokens,
    ),
  );
}
