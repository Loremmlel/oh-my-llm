import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_screen_test_helpers.dart';

void registerFavoriteDetailScreenTests() {
  testWidgets('favorites detail shows user message and assistant content', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(
        db,
        id: 'fav-detail',
        userMessageContent: '这是完整的用户消息内容，用于详情测试',
        assistantContent: '这是完整的模型回复内容，用于详情测试',
        assistantModelDisplayName: 'DeepSeek V4 Flash',
      );
    });

    await tester.tap(find.textContaining('这是完整的用户'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);
    expect(find.text('这是完整的用户消息内容，用于详情测试'), findsOneWidget);
    expect(find.textContaining('这是完整的模型回复内容'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
  });

  testWidgets(
    'favorites detail shows source link and can jump back to chat',
    (tester) async {
      await setUpFavoritesScreen(tester, seed: (db) {
        seedFavorite(
          db,
          id: 'fav-with-source',
          userMessageContent: '有来源的问题',
          assistantContent: '有来源的回复',
          sourceConversationId: 'conv-123',
          sourceConversationTitle: '原始对话',
        );
      });

      await tester.tap(find.text('有来源的问题'));
      await tester.pumpAndSettle();

      expect(find.text('原始对话'), findsOneWidget);

      await tester.tap(find.text('原始对话'));
      await tester.pumpAndSettle();

      expect(find.text('聊天落点'), findsOneWidget);
    },
  );

  testWidgets(
    'favorites detail hides source metadata when source is absent',
    (tester) async {
      await setUpFavoritesScreen(tester, seed: (db) {
        seedFavorite(
          db,
          id: 'fav-no-source',
          userMessageContent: '无来源的问题',
          assistantContent: '无来源的回复',
        );
      });

      await tester.tap(find.text('无来源的问题'));
      await tester.pumpAndSettle();

      expect(find.text('原始对话'), findsNothing);
    },
  );

  testWidgets('favorites detail does not overflow on narrow mobile width', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      viewportSize: const Size(390, 844),
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-mobile-overflow',
          userMessageContent: '移动端溢出回归测试',
          assistantContent: '回复内容',
          sourceConversationId: 'conv-mobile-1',
          sourceConversationTitle:
              '2026-04-09 00:33 这是我准备的OC，你需要根据人类意图进一步压缩布局并防止标题挤出屏幕',
          createdAt: DateTime(2026, 4, 9, 0, 33),
        );
      },
    );

    await tester.tap(find.textContaining('移动端溢出回归测试'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);
    // 回归测试：防止窄屏下收藏详情溢出。
    // takeException() 仅捕获当帧异常，若 Flutter 溢出处理机制变更需更新。
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites detail delete removes favorite and returns to list', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(db, id: 'fav-to-delete', userMessageContent: '要删除的问题', assistantContent: '要删除的回复');
    });

    await tester.tap(find.text('要删除的问题'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);

    await tester.tap(find.byTooltip('删除收藏').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsNothing);
    expect(find.text('暂无收藏'), findsOneWidget);
  });

  testWidgets('favorites detail shows reasoning content when present', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(
        db,
        id: 'fav-reasoning',
        userMessageContent: '有推理的问题',
        assistantContent: '有推理的回复',
        assistantReasoningContent: '这是深度思考的推理过程',
      );
    });

    await tester.tap(find.text('有推理的问题'));
    await tester.pumpAndSettle();

    expect(find.text('深度思考'), findsOneWidget);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    expect(find.text('这是深度思考的推理过程'), findsOneWidget);
  });

  testWidgets('favorites detail hides reasoning panel when absent', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(
        db,
        id: 'fav-no-reasoning',
        userMessageContent: '无推理的问题',
        assistantContent: '无推理的回复',
        assistantReasoningContent: '',
      );
    });

    await tester.tap(find.text('无推理的问题'));
    await tester.pumpAndSettle();

    expect(find.text('无推理的回复'), findsOneWidget);
    expect(find.text('深度思考'), findsNothing);
    expect(find.text('展开'), findsNothing);
  });
}
