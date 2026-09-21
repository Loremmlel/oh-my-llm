import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/presentation/agent_transcript.dart';

import '../../../helpers/async/widget_test_animation.dart';

AgentRunRecord _runningRecord({int extraLines = 0}) => AgentRunRecord(
  id: 'run',
  workspaceId: 'workspace',
  prompt: '核对设定再继续写作',
  startedAt: DateTime(2026),
  steps: [
    AgentStep(label: '模型回复', content: List.filled(30, '先核对人物状态。').join('\n\n')),
    AgentStep(
      label: 'read_document',
      kind: AgentStepKind.tool,
      content: jsonEncode({
        'arguments': {'name': '工作文档'},
        'result': List.generate(
          80 + extraLines,
          (i) => '第 $i 条剧情资料',
        ).join('\n'),
      }),
    ),
  ],
);

void main() {
  for (final mouse in [true, false]) {
    testWidgets('展开末尾工具后${mouse ? '滚轮' : '触摸'}阅读保持位置，回到最新仅滚动一次', (
      tester,
    ) async {
      final width = mouse ? 900.0 : 390.0;
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final record = ValueNotifier(_runningRecord());
      addTearDown(record.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<AgentRunRecord>(
              valueListenable: record,
              builder: (_, value, _) =>
                  AgentTranscript(records: [value], allRuns: [value]),
            ),
          ),
        ),
      );
      await tester.pump();
      final list = find.byType(ListView);
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(position.extentBefore, 0, reason: '打开执行流不自动跳到末尾');
      await tester.tap(find.text('回到最新'));
      await tester.pump();
      final collapsedOffset = position.pixels;
      await tester.tap(find.textContaining('read_document'));
      await settleAnimatedWidgetTransition(tester);
      expect(position.pixels, closeTo(collapsedOffset, 0.01));
      record.value = record.value.copyWith(
        usage: const AgentRunUsage(modelCalls: 1),
      );
      await tester.pump();
      await tester.pump();
      expect(position.pixels, closeTo(collapsedOffset, 0.01));
      await tester.tap(find.text('回到最新'));
      await tester.pump();
      await tester.pump();
      expect(position.extentAfter, closeTo(0, 0.01));
      // 在列表左侧留白处拖动，避免把文本选择误当作列表滚动。
      final point = tester.getCenter(list) + Offset(-width / 2 + 8, 0);
      TestGesture? drag;
      if (mouse) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, -24),
          ),
        );
      } else {
        drag = await tester.startGesture(point);
        await drag.moveBy(const Offset(0, 48));
      }
      await tester.pump();
      final readingOffset = position.pixels;
      expect(position.extentAfter, greaterThan(0));
      // 在触摸尚未结束、鼠标仅滚动很小距离时模拟下一次运行更新。
      record.value = _runningRecord(extraLines: 10)
          .copyWith(usage: const AgentRunUsage(modelCalls: 2));
      await tester.pump();
      await tester.pump();
      final refreshedOffset = position.pixels;
      await drag?.up();
      await tester.pump();
      expect(refreshedOffset, closeTo(readingOffset, 0.01));
      expect(find.text('回到最新'), findsOneWidget);

      if (mouse) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, 1000),
          ),
        );
      } else {
        await tester.tap(find.text('回到最新'));
      }
      await tester.pump();
      await tester.pump();
      expect(position.extentAfter, closeTo(0, 0.01));
      expect(find.text('回到最新'), findsNothing);
      final latestOffset = position.pixels;
      record.value = _runningRecord(extraLines: 30);
      await tester.pump();
      await tester.pump();
      expect(position.pixels, closeTo(latestOffset, 0.01));
      expect(position.extentAfter, greaterThan(0));
      expect(find.text('回到最新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
