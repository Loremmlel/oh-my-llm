import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenSearchTests() {
  testWidgets('history search matches conversation title and user messages', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    // 查询 1（命中对话标题）：防抖窗口未到，搜索未触发，旧结果仍在
    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump();
    expect(find.text('Flutter 路线图'), findsOneWidget);

    // 精确推进公开常量，防抖窗口恰好结束
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);

    // 查询 2（命中用户消息）：同样推进公开常量，直接断言最终结果
    await tester.enterText(find.byType(TextField).first, 'Widget 测试');
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);
  });

  testWidgets('history search does not match assistant replies', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    await tester.enterText(find.byType(TextField).first, '不应匹配');
    // 推进公开防抖时长并重建一帧，直接断言最终结果
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('history search matches user messages across all branches', (
    tester,
  ) async {
    await setUpHistoryScreenWithTree(tester);

    await tester.enterText(find.byType(TextField).first, '分支关键词');
    // 推进公开防抖时长并重建一帧，直接断言最终结果
    await tester.pump(HistoryScreen.searchDebounce);
    await tester.pump();

    expect(find.text('树状会话'), findsOneWidget);
  });
}
