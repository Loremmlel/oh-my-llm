import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_dialog_actions.dart';

import '../../../helpers/async/widget_test_animation.dart';

Future<void> _pressSubmit(
  WidgetTester tester, [
  LogicalKeyboardKey key = LogicalKeyboardKey.enter,
]) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _openDialog(WidgetTester tester, WidgetBuilder builder) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: builder,
            ),
            child: const Text('打开弹窗'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开弹窗'));
  await settleOverlayTransition(tester);
}

void main() {
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('多行输入用 Ctrl+${key.keyLabel} 提交且普通完成动作不提交', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var submitted = 0;
      await _openDialog(
        tester,
        (_) => AppDialogActions(
          onSubmit: () => submitted++,
          child: AlertDialog(
            title: const Text('编辑正文'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '保留正文');
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      expect(submitted, 0);
      await _pressSubmit(tester, key);
      expect(submitted, 1);
      expect(controller.text, '保留正文');
    });
  }

  testWidgets('输入法组合期间取消和提交交给输入法，结束组合后恢复快捷键', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var submitted = 0;
    var cancelled = 0;
    await _openDialog(
      tester,
      (_) => AppDialogActions(
        onCancel: () => cancelled++,
        onSubmit: () => submitted++,
        child: AlertDialog(
          content: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '正在拼音',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.pump();
    await _pressSubmit(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(submitted, 0);
    expect(cancelled, 0);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '正在拼音',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    await _pressSubmit(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(submitted, 1);
    expect(cancelled, 1);
  });

  testWidgets('禁止遮罩关闭时 Esc 仍可取消，PopScope 忙碌时保留弹窗', (tester) async {
    var busy = true;
    StateSetter? setDialogState;
    await _openDialog(
      tester,
      (_) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          return PopScope<void>(
            canPop: !busy,
            child: const AppDialogActions(
              child: AlertDialog(title: Text('处理中')),
            ),
          );
        },
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlayTransition(tester);
    expect(find.text('处理中'), findsOneWidget);
    setDialogState!(() => busy = false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlayTransition(tester);
    expect(find.text('处理中'), findsNothing);
  });

  testWidgets('关闭确认框只取消最上层，焦点恢复后父弹窗可以再次提交', (tester) async {
    var submitted = 0;
    await _openDialog(
      tester,
      (context) => AppDialogActions(
        onSubmit: () => submitted++,
        onCancel: () => showDialog<bool>(
          context: context,
          builder: (_) => const AppConfirmDialog(
            title: '放弃修改？',
            message: '已保存的内容保留。',
            confirmLabel: '放弃',
          ),
        ),
        child: const AlertDialog(title: Text('父弹窗')),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlayTransition(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleOverlayTransition(tester);
    expect(find.text('放弃修改？'), findsNothing);
    expect(find.text('父弹窗'), findsOneWidget);
    await _pressSubmit(tester);
    expect(submitted, 1);
  });

  testWidgets('提交不可用时快捷键没有副作用，长按提交只执行首次按下', (tester) async {
    var enabled = false;
    var submitted = 0;
    StateSetter? setDialogState;
    await _openDialog(
      tester,
      (_) => StatefulBuilder(
        builder: (context, setState) {
          setDialogState = setState;
          return AppDialogActions(
            onSubmit: enabled ? () => submitted++ : null,
            child: const AlertDialog(title: Text('提交内容')),
          );
        },
      ),
    );
    await _pressSubmit(tester);
    expect(submitted, 0);
    setDialogState!(() => enabled = true);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(submitted, 1);
  });
}
