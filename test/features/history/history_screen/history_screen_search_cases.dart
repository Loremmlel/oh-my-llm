import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenSearchTests() {
  testWidgets('history screen debounces search input before filtering', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();

    await pumpHistoryScreen(tester, preferences: preferences);

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(const Duration(milliseconds: 299));

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);
  });

  testWidgets('history screen searches only title and user messages', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();

    await pumpHistoryScreen(tester, preferences: preferences);

    await tester.enterText(find.byType(TextField).first, 'Rust');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Rust 重构计划'), findsOneWidget);
    expect(find.text('Flutter 路线图'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Widget 测试');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Flutter 路线图'), findsOneWidget);
    expect(find.text('Rust 重构计划'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '不应匹配');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('history search matches user messages across all branches', (
    tester,
  ) async {
    final preferences = await createTreeSeededPreferences();

    await pumpHistoryScreen(tester, preferences: preferences);

    await tester.enterText(find.byType(TextField).first, '分支关键词');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('树状会话'), findsOneWidget);
  });
}
