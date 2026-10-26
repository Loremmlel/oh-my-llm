import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/app/router/app_material_route.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_editor.dart';

import '../../../helpers/predictive_back_gesture.dart';

void main() {
  testWidgets('预测返回可取消和提交，修改后拦截，恢复原文后重新放行', (tester) async {
    final router = GoRouter(
      routes: [
        appMaterialRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('打开'),
            ),
          ),
        ),
        appMaterialRoute(
          path: '/edit',
          builder: (_, _) => PresetPromptEditor(
            initialValue: PresetPrompt(
              id: 'p',
              name: '原名称',
              messages: const [],
              updatedAt: DateTime(2026),
            ),
            onSubmit: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.lightTheme(), routerConfig: router),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final editor = find.byType(PresetPromptEditor);
    final editorState = tester.state(editor);
    final route = ModalRoute.of(tester.element(editor))!;
    expect(route.popGestureEnabled, isTrue);
    expect(route.isCurrent, isTrue);

    await sendPredictiveBackEvent(tester, 'startBackGesture');
    expect(route.popGestureInProgress, isTrue, reason: '系统通道开始手势');
    await tester.pump();
    await sendPredictiveBackEvent(
      tester,
      'updateBackGestureProgress',
      progress: 0.4,
    );
    await tester.pumpAndSettle();
    expect(route.popGestureInProgress, isTrue);
    expect(tester.getTopLeft(editor).dx, greaterThan(0));
    await sendPredictiveBackEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(tester.state(editor), same(editorState));
    expect(route.isCurrent, isTrue);

    final nameField = find.widgetWithText(AppTextField, '预设 Prompt 名称');
    await tester.enterText(nameField, '修改名称');
    await tester.pump();
    expect(route.popGestureEnabled, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(find.text('修改名称'), findsOneWidget);

    await tester.enterText(nameField, '原名称');
    await tester.pump();
    expect(route.popGestureEnabled, isTrue);
    await sendPredictiveBackEvent(tester, 'startBackGesture');
    await tester.pump();
    await sendPredictiveBackEvent(
      tester,
      'updateBackGestureProgress',
      progress: 0.6,
    );
    await tester.pumpAndSettle();
    await sendPredictiveBackEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(editor, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('手机键盘改变高度时长正文选区自动可见并保留焦点和输入框身份', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = List.generate(60, (i) => '第 $i 行：用于检查键盘避让的长正文。').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: PresetPromptEditor(
          initialValue: PresetPrompt(
            id: 'p',
            name: '预设',
            updatedAt: DateTime(2026),
            messages: [
              PromptMessage(
                id: 'm',
                title: '规则',
                role: PromptMessageRole.system,
                content: content,
              ),
            ],
          ),
          onSubmit: (_) async {},
        ),
      ),
    );
    final field = find.widgetWithText(AppTextField, 'Prompt 内容');
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(field);
    final value = TextEditingValue(
      text: content,
      selection: const TextSelection.collapsed(offset: 0),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump(const Duration(milliseconds: 16));
    final original = tester.state<EditableTextState>(editable);
    final originalSize = tester.getSize(editable);
    for (final bottom in [80.0, 160.0, 240.0, 340.0, 440.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.state<EditableTextState>(editable), same(original));
      expect(original.widget.focusNode.hasFocus, isTrue);
      expect(original.widget.controller.value, value);
      expect(tester.getSize(editable).width, originalSize.width);
      expect(find.text('保存').hitTestable(), findsOneWidget);
      final render = original.renderEditable;
      final caret = render.getLocalRectForCaret(value.selection.extent);
      expect(
        render.localToGlobal(caret.bottomRight).dy,
        lessThan(844 - bottom),
        reason: '键盘高 $bottom 时选区末端应自动出现在键盘上方',
      );
      expect(render.localToGlobal(caret.topLeft).dy, greaterThan(56));
    }
    // 从可见正文拖到末尾，不能停在键盘后面的内部滚动底部。
    final render = original.renderEditable;
    final start = render.localToGlobal(
      render.getLocalRectForCaret(value.selection.extent).center,
    );
    await tester.dragFrom(start + const Offset(40, 0), const Offset(0, -4000));
    await tester.pumpAndSettle();
    final end = render.getLocalRectForCaret(
      TextPosition(offset: content.length),
    );
    expect(render.localToGlobal(end.bottomRight).dy, lessThan(844 - 440));
    expect(render.localToGlobal(end.topLeft).dy, greaterThan(56));
    final editedValue = TextEditingValue(
      text: '$content\n继续编辑',
      selection: TextSelection.collapsed(offset: content.length + 5),
      composing: TextRange(start: content.length + 1, end: content.length + 5),
    );
    tester.testTextInput.updateEditingValue(editedValue);
    await tester.pumpAndSettle();
    final editedCaret = render.getLocalRectForCaret(
      editedValue.selection.extent,
    );
    expect(
      render.localToGlobal(editedCaret.bottomRight).dy,
      lessThan(844 - 440),
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.state<EditableTextState>(editable), same(original));
    expect(original.widget.controller.value, editedValue);
  });

  testWidgets('预设页面保存失败保留输入，返回确认取消后继续编辑', (tester) async {
    PresetPromptFormData? submitted;
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
            onSubmit: (data) async {
              submitted = data;
              throw StateError('测试保存失败');
            },
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(AppTextField, '预设 Prompt 名称'),
      '修改名称',
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('测试保存失败'), findsOneWidget);
    expect(find.text('修改名称'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(AppTextField, '自定义 CoT 标签（可选）'),
      'thinking_diy',
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(submitted!.customReasoningTag, 'thinking_diy');
    submitted = null;
    await tester.enterText(
      find.widgetWithText(AppTextField, '自定义 CoT 标签（可选）'),
      '<thinking_diy>',
    );
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('只填写标签名'), findsOneWidget);
    expect(submitted, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(find.text('修改名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
