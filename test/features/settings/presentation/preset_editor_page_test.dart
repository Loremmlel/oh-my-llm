import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_editor.dart';

import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('预设页面保存失败保留输入，返回确认取消后继续编辑', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('打开'),
            ),
          ),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, _) => PresetPromptEditor(
            initialValue: PresetPrompt(
              id: 'p',
              name: '原名称',
              messages: const [],
              updatedAt: DateTime(2026),
            ),
            onSubmit: (_) async => throw StateError('测试保存失败'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('打开'));
    await settleRouteTransition(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, '预设 Prompt 名称'),
      '修改名称',
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('测试保存失败'), findsOneWidget);
    expect(find.text('修改名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await settleOverlayTransition(tester);
    expect(find.text('修改名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('放弃修改'));
    await settleRouteTransition(tester);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
