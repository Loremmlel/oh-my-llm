import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/async/widget_test_animation.dart';
import 'history_screen_test_helpers.dart';

/// 按住修饰键点击指定文本对应的会话行。
Future<void> _tapWithModifiers(
  WidgetTester tester,
  String rowText, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.tap(find.text(rowText));
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pump();
}

/// 打开第一行的 overflow 菜单并点击指定动作。
Future<void> _openFirstRowMenuAndTap(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('更多操作').first);
  await settleOverlayTransition(tester);
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, action).last);
  await settleOverlayTransition(tester);
}

void registerHistoryScreenActionsTests() {
  testWidgets('普通态整行点击导航到对应会话', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.tap(find.text('Flutter 路线图'));
    await settleRouteTransition(tester);

    expect(find.text('聊天落点'), findsOneWidget);
  });

  testWidgets('长按进入选择后整行点击只切换选择而不导航', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();
    await tester.tap(find.text('项目复盘'));
    await tester.pump();

    expect(find.text('聊天落点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 2 项'), findsOneWidget);
  });

  testWidgets('Ctrl 点击切换选择且不触发导航', (tester) async {
    await setUpHistoryScreen(tester);

    await _tapWithModifiers(tester, 'Flutter 路线图', control: true);

    expect(find.text('聊天落点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsOneWidget);
  });

  testWidgets('Shift 点击选择当前页闭区间', (tester) async {
    await setUpHistoryScreen(tester);

    // 列表按更新时间排序：Rust 重构计划与 Flutter 路线图相邻。
    // 先 Ctrl 点击建立锚点，再 Shift 点击取闭区间。
    await _tapWithModifiers(tester, 'Rust 重构计划', control: true);
    await _tapWithModifiers(tester, 'Flutter 路线图', shift: true);

    expect(find.widgetWithText(FilledButton, '删除 2 项'), findsOneWidget);
  });

  testWidgets('Ctrl+A 选择当前页全部会话', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.textContaining('已选择 3 项'), findsOneWidget);
  });

  testWidgets('Esc 退出选择模式', (tester) async {
    await setUpHistoryScreen(tester);
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byTooltip('退出选择'), findsNothing);
    expect(find.textContaining('已选择'), findsNothing);
  });

  testWidgets('Delete 弹出批量删除确认', (tester) async {
    await setUpHistoryScreen(tester);
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settleOverlayTransition(tester);

    expect(find.text('删除选中的对话'), findsOneWidget);
    // 仅弹出确认，尚未执行删除。
    expect(find.text('Flutter 路线图'), findsOneWidget);
  });

  testWidgets('通过行内 overflow 菜单选择会话', (tester) async {
    await setUpHistoryScreen(tester);

    await _openFirstRowMenuAndTap(tester, '选择');

    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsOneWidget);
  });

  testWidgets('通过行内 overflow 菜单重命名会话', (tester) async {
    await setUpHistoryScreen(tester);

    await _openFirstRowMenuAndTap(tester, '重命名');
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的历史标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settleOverlayTransition(tester);

    expect(find.text('新的历史标题'), findsOneWidget);
  });

  testWidgets('overflow 单项删除需确认且取消不删除', (tester) async {
    await setUpHistoryScreen(tester);

    await _openFirstRowMenuAndTap(tester, '删除');
    await settleOverlayTransition(tester);
    expect(find.text('删除选中的对话'), findsOneWidget);

    // 取消：会话仍在列表中。
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });

  testWidgets('右键打开行上下文菜单并可发起删除', (tester) async {
    await setUpHistoryScreen(tester);

    final row = find.text('Flutter 路线图');
    final center = tester.getCenter(row);
    await tester.tapAt(center, buttons: kSecondaryMouseButton);
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '删除').last);
    await settleOverlayTransition(tester);

    expect(find.text('删除选中的对话'), findsOneWidget);
  });

  testWidgets('系统返回先清除历史选择态再离开页面', (tester) async {
    await setUpHistoryScreen(tester);
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();

    expect(find.byTooltip('退出选择'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();

    // 选择态是页面本地返回目标，Back 优先清选择而非离开页面。
    expect(find.byTooltip('退出选择'), findsNothing);
    expect(find.text('聊天落点'), findsNothing);
    expect(find.text('Flutter 路线图'), findsOneWidget);
  });

  testWidgets('批量删除确认后按真实结果刷新当前窗口', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();
    await tester.longPress(find.text('项目复盘'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '删除 2 项'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await settleOverlayTransition(tester);

    expect(find.text('Flutter 路线图'), findsNothing);
    expect(find.text('项目复盘'), findsNothing);
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });
}
