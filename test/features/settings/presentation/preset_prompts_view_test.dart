import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/lists/preset_prompts_view.dart';

import '../../../helpers/fixtures.dart';

void main() {
  testWidgets('预设操作等待时防止重复提交且失败后允许重试', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: PresetPromptsView(
            templates: [TestFixtures.presetPrompt(id: 'pending')],
            onCopy: (_) {
              calls++;
              return calls == 1 ? pending.future : Future.value();
            },
            onEdit: (_) {},
            onDelete: (_) async {},
            onSingleSystemChanged: (_, _) async {},
          ),
        ),
      ),
    );
    final copy = find.widgetWithText(TextButton, '复制');
    await tester.tap(copy);
    await tester.pump();
    expect(tester.widget<TextButton>(copy).onPressed, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    pending.completeError(StateError('模拟写入失败'));
    await tester.pump();
    expect(find.text('操作失败，请重试'), findsOneWidget);
    await tester.tap(copy);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('操作失败，请重试'), findsNothing);
  });

  testWidgets('窄屏两倍字号保留预设操作且不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PresetPromptsView(
                  templates: [
                    TestFixtures.presetPrompt(
                      id: 'narrow',
                      name: '较长名称用于检查窄屏字号变化与操作布局',
                    ),
                  ],
                  onCopy: (_) async {},
                  onEdit: (_) {},
                  onDelete: (_) async {},
                  onSingleSystemChanged: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, '编辑'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '复制'), findsOneWidget);
    expect(find.byTooltip('预设操作'), findsOneWidget);
  });
}
