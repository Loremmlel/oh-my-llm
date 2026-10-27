import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/protocols/llm_response_accumulator.dart';

void main() {
  for (final thinkingFirst in [false, true]) {
    test('请求计时包含首段${thinkingFirst ? '思考' : '正文'}前的等待，用量事件不触发首字', () {
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
      expect(result.usage?.outputDuration, const Duration(seconds: 12));
      expect(result.usage?.tokensPerSecond, 5);
      expect(result.usage?.timeToFirstToken, const Duration(seconds: 10));
    });
  }

  test('只有工具参数或用量事件时使用请求耗时，首字时间保持未知', () {
    final accumulator = LlmResponseAccumulator(
      elapsed: () => const Duration(seconds: 2),
    );
    accumulator.add(
      const LlmToolArgumentsDelta(index: 0, argumentsDelta: '{}'),
    );
    accumulator.add(const LlmEvent(usage: LlmUsage(outputTokens: 10)));
    final usage = accumulator.finish().usage;
    expect(usage?.tokensPerSecond, 5);
    expect(usage?.timeToFirstToken, isNull);
  });

  test('未报告用量仍保留首字时间，速度保持未知', () {
    var elapsed = const Duration(seconds: 3);
    final accumulator = LlmResponseAccumulator(elapsed: () => elapsed);
    accumulator.add(const LlmEvent(contentDelta: '正文'));
    elapsed = const Duration(seconds: 5);
    final usage = accumulator.finish().usage;
    expect(usage?.timeToFirstToken, const Duration(seconds: 3));
    expect(usage?.tokensPerSecond, isNull);
    expect(LlmUsage.fromJson(usage?.toJson()), usage);
  });
}
