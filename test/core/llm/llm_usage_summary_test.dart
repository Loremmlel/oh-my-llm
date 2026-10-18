import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_usage_summary.dart';

void main() {
  test('累计用量避免重复计算缓存和推理，命中率按已报告缓存的输入加权', () {
    final summary = LlmUsageSummary.fromUsages([
      const LlmUsage(
        inputTokens: 100,
        cachedInputTokens: 50,
        cacheWriteInputTokens: 20,
        outputTokens: 30,
        reasoningTokens: 10,
      ),
      const LlmUsage(
        inputTokens: 300,
        cachedInputTokens: 100,
        outputTokens: 70,
      ),
      const LlmUsage(inputTokens: 200, outputTokens: 20),
    ]);
    expect(summary.tokens.totalTokens, 720);
    expect(summary.tokens.uncachedInputTokens, 450);
    expect(summary.tokens.cachedInputTokens, 150);
    expect(summary.cacheHitRate, .375);
    expect(summary.incomplete, isFalse);
  });

  test('缺报调用保留已有用量并标记部分统计，空对话保持未知总量', () {
    final summary = LlmUsageSummary.fromUsages([
      null,
      const LlmUsage(inputTokens: 100, outputTokens: 20),
      const LlmUsage(outputTokens: 5),
    ]);
    expect(summary.tokens.totalTokens, 125);
    expect(summary.incomplete, isTrue);
    expect(summary.cacheHitRate, isNull);
    expect(LlmUsageSummary.fromUsages([]), const LlmUsageSummary());
  });
}
