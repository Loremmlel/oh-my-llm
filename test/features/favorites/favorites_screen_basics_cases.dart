import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';

import '../../test_database.dart';
import 'favorites_screen_test_helpers.dart';

void registerFavoritesScreenBasicsTests() {
  testWidgets('favorites screen shows empty state message', (tester) async {
    final preferences = await createEmptyPreferences();

    await pumpFavoritesScreen(tester, preferences: preferences);

    expect(
      find.text('暂无收藏。在聊天页点击模型回复的书签图标开始收藏。'),
      findsOneWidget,
    );
  });

  testWidgets('favorites screen renders favorites list items', (tester) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-1',
      userMessageContent: '这是用户问题',
      assistantContent: '这是模型回复',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    expect(find.text('这是用户问题'), findsOneWidget);
    expect(find.text('这是模型回复'), findsOneWidget);
  });

  testWidgets('favorites screen uncategorized filter shows correct items', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-1',
      userMessageContent: '未分类问题',
      assistantContent: '未分类回复',
      collectionId: null,
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.widgetWithText(FilterChip, '未分类'));
    await tester.pumpAndSettle();

    expect(find.text('未分类问题'), findsOneWidget);
    expect(find.text('未分类回复'), findsOneWidget);
  });

  testWidgets('favorites screen collection filter shows empty state when empty', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedCollection(database, id: 'col-1', name: '我的收藏夹');

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.widgetWithText(FilterChip, '我的收藏夹'));
    await tester.pumpAndSettle();

    expect(find.text('该收藏夹暂无收藏。'), findsOneWidget);
  });

  testWidgets('favorites screen uncategorized filter shows empty state when empty', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = AppDatabase.inMemory();

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.widgetWithText(FilterChip, '未分类'));
    await tester.pumpAndSettle();

    expect(find.text('未分类下暂无收藏。'), findsOneWidget);
  });

  testWidgets('favorites screen tapping item navigates to detail', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-1',
      userMessageContent: '导航测试问题',
      assistantContent: '导航测试回复',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.text('导航测试问题'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);
  });
}
