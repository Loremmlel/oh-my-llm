import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

void main() {
  test('已有用量 JSON 保持键名及未知值语义', () {
    const usage = LlmUsage(
      inputTokens: 10,
      outputTokens: 20,
      cachedInputTokens: 0,
    );
    expect(LlmUsage.fromJson(usage.toJson()), usage);
    expect(usage.toJson(), {
      'inputTokens': 10,
      'outputTokens': 20,
      'reasoningTokens': null,
      'cachedInputTokens': 0,
      'cacheWriteInputTokens': null,
    });
    expect(LlmUsage.fromJson({'inputTokens': -1, 'outputTokens': '2'}), isNull);
  });
  test('单请求累计快照按字段覆盖而不相加', () {
    const initial = LlmUsage(
      inputTokens: 30,
      outputTokens: 5,
      cachedInputTokens: 8,
    );
    expect(
      initial.merge(const LlmUsage(outputTokens: 10, cachedInputTokens: 0)),
      const LlmUsage(inputTokens: 30, outputTokens: 10, cachedInputTokens: 0),
    );
  });

  test('速度使用已报告输出和请求耗时，首字时间保存重开后保持一致', () {
    const usage = LlmUsage(
      inputTokens: 100,
      cachedInputTokens: 40,
      cacheWriteInputTokens: 20,
      outputTokens: 30,
      reasoningTokens: 10,
      outputDuration: Duration(seconds: 2),
      timeToFirstToken: Duration(milliseconds: 500),
    );
    expect(usage.tokensPerSecond, 15);
    expect(usage.uncachedInputTokens, 60);
    expect(usage.totalTokens, 130);
    expect(LlmUsage.fromJson(usage.toJson()), usage);
    for (final missing in [
      const LlmUsage(outputTokens: 30),
      const LlmUsage(outputDuration: Duration(seconds: 2)),
      const LlmUsage(outputTokens: 30, outputDuration: Duration.zero),
    ]) {
      expect(missing.tokensPerSecond, isNull);
    }
  });

  test('未缓存输入对负数和零输入归零，未知输入保持未知', () {
    expect(const LlmUsage(inputTokens: -1).uncachedInputTokens, 0);
    expect(const LlmUsage(inputTokens: 0).uncachedInputTokens, 0);
    expect(const LlmUsage().uncachedInputTokens, isNull);
  });
}
