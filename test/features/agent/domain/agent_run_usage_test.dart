import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/features/agent/domain/agent_run_usage.dart';

void main() {
  test('多次调用累计所有已报告字段，未报告字段保持未知', () {
    final first = const AgentRunUsage().startCall().addResponse(
      const LlmUsage(inputTokens: 100, outputTokens: 10, cachedInputTokens: 40),
    );
    final total = first.startCall().addResponse(
      const LlmUsage(
        inputTokens: 150,
        outputTokens: 20,
        cachedInputTokens: 60,
        cacheWriteInputTokens: 5,
      ),
    );
    expect(total.modelCalls, 2);
    expect(
      total.tokens,
      const LlmUsage(
        inputTokens: 250,
        outputTokens: 30,
        cachedInputTokens: 100,
        cacheWriteInputTokens: 5,
      ),
    );
    expect(total.incomplete, isFalse);
    expect(first.modelCalls, 1);
    expect(first.tokens!.inputTokens, 100);
  });

  test('响应缺失或只有部分用量时保留已知值，后续成功不清除缺报标记', () {
    for (final missing in [null, const LlmUsage(inputTokens: 5)]) {
      final partial = const AgentRunUsage().startCall().addResponse(missing);
      final total = partial.startCall().addResponse(
        const LlmUsage(inputTokens: 10, outputTokens: 0),
      );
      expect(total.modelCalls, 2);
      expect(total.tokens!.inputTokens, missing == null ? 10 : 15);
      expect(total.tokens!.outputTokens, 0);
      expect(total.tokens!.reasoningTokens, isNull);
      expect(total.incomplete, isTrue);
    }
  });

  test('汇总子任务时累计调用与推理用量，未完成或缺报的子任务使汇总不完整', () {
    const root = AgentRunUsage(
      modelCalls: 1,
      tokens: LlmUsage(inputTokens: 10, outputTokens: 2, reasoningTokens: 1),
    );
    const child = AgentRunUsage(
      modelCalls: 2,
      tokens: LlmUsage(inputTokens: 20, outputTokens: 3, reasoningTokens: 2),
    );
    final complete = root.add(child, completed: true);
    expect(complete.modelCalls, 3);
    expect(
      complete.tokens,
      const LlmUsage(inputTokens: 30, outputTokens: 5, reasoningTokens: 3),
    );
    expect(complete.incomplete, isFalse);
    expect(root.add(child, completed: false).incomplete, isTrue);
    expect(
      complete
          .add(const AgentRunUsage(incomplete: true), completed: true)
          .incomplete,
      isTrue,
    );
    expect(
      complete.add(const AgentRunUsage(), completed: false).tokens,
      complete.tokens,
    );
  });
}
