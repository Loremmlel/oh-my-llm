import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/widget_test_animation.dart';
import 'history_screen_test_helpers.dart';

void registerHistoryScreenActionsTests() {
  testWidgets('history screen renames a conversation', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.tap(find.byTooltip('重命名会话').first);
    await settleOverlayTransition(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的历史标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    // 重命名对话框出场，改名 Future 与本地标题修正随帧完成
    await settleOverlayTransition(tester);

    expect(find.text('新的历史标题'), findsOneWidget);
  });

  testWidgets('history screen batch selects and deletes conversations', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    await tester.longPress(find.text('Flutter 路线图'));
    // 长按只切换选中集合，单帧即可
    await tester.pump();
    await tester.longPress(find.text('项目复盘'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '删除 2 项'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    // 确认对话框出场，删除 Future 随帧完成并本地移除
    await settleOverlayTransition(tester);

    expect(find.text('Flutter 路线图'), findsNothing);
    expect(find.text('项目复盘'), findsNothing);
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });

  testWidgets('history screen jumps back to chat with selected conversation', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    await tester.tap(find.text('Flutter 路线图'));
    await settleRouteTransition(tester);

    expect(find.text('聊天落点'), findsOneWidget);
  });

  testWidgets('history screen checkbox selects without triggering navigation', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    await tester.tap(find.byType(Checkbox).first);
    // 复选框只切换选中集合，单帧即可
    await tester.pump();

    expect(find.text('聊天落点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsOneWidget);
  });

  testWidgets('系统返回先清除历史选择态再离开页面', (tester) async {
    await setUpHistoryScreen(tester);
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pump();

    expect(find.byTooltip('取消选择'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();

    // 选择态是页面本地返回目标，Back 优先清选择而非离开页面。
    expect(find.byTooltip('取消选择'), findsNothing);
    expect(find.text('聊天落点'), findsNothing);
    expect(find.text('Flutter 路线图'), findsOneWidget);
  });
}
