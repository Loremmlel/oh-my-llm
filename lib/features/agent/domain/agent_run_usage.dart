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
    tokens: reported == null ? tokens : tokens?.add(reported) ?? reported,
    incomplete:
        incomplete ||
        reported?.inputTokens == null ||
        reported?.outputTokens == null,
  );

  AgentRunUsage add(AgentRunUsage other, {required bool completed}) =>
      AgentRunUsage(
        modelCalls: modelCalls + other.modelCalls,
        tokens: other.tokens == null
            ? tokens
            : tokens?.add(other.tokens!) ?? other.tokens,
        incomplete: incomplete || other.incomplete || !completed,
      );

  @override
  List<Object?> get props => [modelCalls, tokens, incomplete];
}
