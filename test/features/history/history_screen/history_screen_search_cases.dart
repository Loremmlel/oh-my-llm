import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenSearchTests() {
  testWidgets('搜索匹配会话标题与用户消息', (tester) async {
    await setUpHistoryScreen(tester);

    // 查询 1（命中标题）：防抖窗口未到，搜索未触发，旧结果仍在。
    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump();
    expect(find.text('Flutter 路线图'), findsOneWidget);

    // 精确推进公开常量，防抖窗口恰好结束。
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);

    // 查询 2（命中用户消息）：同样推进公开常量，直接断言最终结果。
    await tester.enterText(find.byType(TextField).first, 'Widget 测试');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);
  });

  testWidgets('搜索不匹配 assistant 回复内容', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.enterText(find.byType(TextField).first, '不应匹配');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('搜索匹配所有分支上的用户消息', (tester) async {
    await setUpHistoryScreenWithTree(tester);

    await tester.enterText(find.byType(TextField).first, '分支关键词');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('树状会话'), findsOneWidget);
  });

  testWidgets('搜索框提供清空按钮并恢复完整列表', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    expect(find.text('Flutter 路线图'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsOneWidget);
  });

  testWidgets('无结果空状态提供清除关键词入口', (tester) async {
    await setUpHistoryScreen(tester);

    await tester.enterText(find.byType(TextField).first, '不存在的关键词');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();
    expect(find.textContaining('没有匹配'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清除搜索'));
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.textContaining('没有匹配'), findsNothing);
  });

  testWidgets('搜索生效时清空防抖窗口内的选择', (tester) async {
    await setUpHistoryScreen(tester);

    // 输入搜索词但防抖尚未到期，此时用 Ctrl 点击建立选择
    // （点击类手势不推进假时钟，防抖计时不受干扰）。
    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Rust 重构计划'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.textContaining('已选择 1 项'), findsOneWidget);

    // 防抖到期、搜索生效后选择态被清空。
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.textContaining('已选择'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsNothing);
  });
}
