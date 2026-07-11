import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/history/presentation/history_screen.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenSearchTests() {
  testWidgets('history screen searches only title and user messages', (
    tester,
  ) async {
    await setUpHistoryScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(HistoryScreen.searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Widget 测试');
    await tester.pump(HistoryScreen.searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '不应匹配');
    await tester.pump(HistoryScreen.searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('history search matches user messages across all branches', (
    tester,
  ) async {
    await setUpHistoryScreenWithTree(tester);

    await tester.enterText(find.byType(TextField).first, '分支关键词');
    await tester.pump(HistoryScreen.searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('树状会话'), findsOneWidget);
  });
}
