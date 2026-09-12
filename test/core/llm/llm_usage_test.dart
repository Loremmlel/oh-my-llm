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
}
