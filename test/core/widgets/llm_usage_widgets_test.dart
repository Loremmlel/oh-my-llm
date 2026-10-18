import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/widgets/llm_usage_widgets.dart';

void main() {
  testWidgets('回复缺少可展示用量时隐藏速度行，已报告零输出仍然显示', (tester) async {
    Future<void> showUsage(LlmUsage usage) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LlmReplyUsage(usage: usage)),
      ),
    );
    for (final usage in [
      const LlmUsage(),
      const LlmUsage(reasoningTokens: 5),
      const LlmUsage(outputDuration: Duration(seconds: 1)),
    ]) {
      await showUsage(usage);
      expect(find.textContaining('TPS'), findsNothing);
    }
    await showUsage(const LlmUsage(outputTokens: 0));
    expect(find.text('输出 0'), findsOneWidget);
    expect(find.text('· TPS —'), findsOneWidget);
  });
}
