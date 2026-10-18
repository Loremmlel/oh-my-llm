import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_response_accumulator.dart';

void main() {
  for (final thinkingFirst in [false, true]) {
    test('首段${thinkingFirst ? '思考' : '正文'}开始计时，忽略之前的等待与用量事件', () {
      var elapsed = Duration.zero;
      final accumulator = LlmResponseAccumulator(elapsed: () => elapsed);
      accumulator.add(const LlmEvent(usage: LlmUsage(inputTokens: 100)));
      elapsed = const Duration(seconds: 10);
      accumulator.add(
        thinkingFirst
            ? const LlmEvent(reasoningDelta: '思考')
            : const LlmEvent(contentDelta: '正文'),
      );
      elapsed = const Duration(seconds: 12);
      accumulator.add(
        const LlmEvent(contentDelta: '完成', usage: LlmUsage(outputTokens: 60)),
      );
      final result = accumulator.finish();
      expect(result.usage?.outputDuration, const Duration(seconds: 2));
      expect(result.usage?.tokensPerSecond, 30);
    });
  }

  test('只有工具参数或用量事件时不伪造正文生成耗时', () {
    final accumulator = LlmResponseAccumulator();
    accumulator.add(
      const LlmToolArgumentsDelta(index: 0, argumentsDelta: '{}'),
    );
    accumulator.add(const LlmEvent(usage: LlmUsage(outputTokens: 10)));
    expect(accumulator.finish().usage?.tokensPerSecond, isNull);
  });
}
