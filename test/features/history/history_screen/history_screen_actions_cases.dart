import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';

import 'history_screen_test_helpers.dart';

void registerHistoryScreenActionsTests() {
  testWidgets('history screen renames and batch deletes conversations', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createSeededPreferences(database);

    await pumpHistoryScreen(tester, preferences: preferences, database: database);

    await tester.tap(find.byTooltip('重命名会话').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的历史标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的历史标题'), findsOneWidget);

    await tester.longPress(find.text('新的历史标题'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Flutter 路线图'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除 2 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(find.text('新的历史标题'), findsNothing);
    expect(find.text('Flutter 路线图'), findsNothing);
    expect(find.text('项目复盘'), findsOneWidget);
  });

  testWidgets('history screen jumps back to chat with selected conversation', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createSeededPreferences(database);

    await pumpHistoryScreen(tester, preferences: preferences, database: database);

    await tester.tap(find.text('Flutter 路线图'));
    await tester.pumpAndSettle();

    expect(find.text('聊天落点'), findsOneWidget);
  });

  testWidgets('history screen checkbox selects without triggering navigation', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createSeededPreferences(database);

    await pumpHistoryScreen(tester, preferences: preferences, database: database);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('聊天落点'), findsNothing);
    expect(find.widgetWithText(FilledButton, '删除 1 项'), findsOneWidget);
  });
}
