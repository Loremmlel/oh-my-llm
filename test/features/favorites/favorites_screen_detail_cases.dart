import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_database.dart';
import 'favorites_screen_test_helpers.dart';

void registerFavoriteDetailScreenTests() {
  testWidgets('favorites detail shows user message and assistant content', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-detail',
      userMessageContent: '这是完整的用户消息内容，用于详情测试',
      assistantContent: '这是完整的模型回复内容，用于详情测试',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.textContaining('这是完整的用户'));
    await tester.pumpAndSettle();

    // Detail screen title
    expect(find.text('收藏详情'), findsOneWidget);

    // User message rendered via SelectableText
    expect(find.text('这是完整的用户消息内容，用于详情测试'), findsOneWidget);

    // Assistant content rendered via MarkdownBody
    expect(find.textContaining('这是完整的模型回复内容'), findsOneWidget);
  });

  testWidgets('favorites detail shows go-to-conversation button when source set', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-with-source',
      userMessageContent: '有来源的问题',
      assistantContent: '有来源的回复',
      sourceConversationId: 'conv-123',
      sourceConversationTitle: '原始对话',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.text('有来源的问题'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('跳转到来源对话'), findsOneWidget);
  });

  testWidgets('favorites detail without source conversation has no go-to button', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-no-source',
      userMessageContent: '无来源的问题',
      assistantContent: '无来源的回复',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.text('无来源的问题'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('跳转到来源对话'), findsNothing);
  });

  testWidgets('favorites detail delete removes favorite and returns to list', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedFavorite(
      database,
      id: 'fav-to-delete',
      userMessageContent: '要删除的问题',
      assistantContent: '要删除的回复',
    );

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.text('要删除的问题'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);

    // Tap AppBar delete button
    await tester.tap(find.byTooltip('删除收藏').first);
    await tester.pumpAndSettle();

    // Confirm delete in dialog
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    // Back to favorites list, which is now empty
    expect(find.text('收藏详情'), findsNothing);
    expect(
      find.text('暂无收藏。在聊天页点击模型回复的书签图标开始收藏。'),
      findsOneWidget,
    );
  });
}
