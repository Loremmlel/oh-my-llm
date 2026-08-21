import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

void registerFavoriteDetailScreenTests() {
  testWidgets('favorites detail shows user message and assistant content', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-detail',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-detail',
          userMessageContent: '这是完整的用户消息内容，用于详情测试',
          assistantContent: '这是完整的模型回复内容，用于详情测试',
          assistantModelDisplayName: 'DeepSeek V4 Flash',
        );
      },
    );

    expect(find.text('收藏详情'), findsOneWidget);
    expect(find.text('这是完整的用户消息内容，用于详情测试'), findsOneWidget);
    expect(find.textContaining('这是完整的模型回复内容'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
  });

  testWidgets('favorites detail shows source link and can jump back to chat', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-with-source',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-with-source',
          userMessageContent: '有来源的问题',
          assistantContent: '有来源的回复',
          sourceConversationId: 'conv-123',
          sourceConversationTitle: '原始对话',
        );
      },
    );

    expect(find.text('原始对话'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.text('原始对话')));

    await tester.tap(find.text('原始对话'));
    await settleRouteTransition(tester);

    // 生产路由下聊天页是真实 ChatScreen，用路由位置断言跳转成功。
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      AppDestination.chat.path,
    );
  });

  testWidgets('favorites detail hides source metadata when source is absent', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-no-source',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-no-source',
          userMessageContent: '无来源的问题',
          assistantContent: '无来源的回复',
        );
      },
    );

    expect(find.text('原始对话'), findsNothing);
  });

  testWidgets('favorites detail does not overflow on narrow mobile width', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      viewportSize: const Size(390, 844),
      initialLocation: '/favorites/items/fav-mobile-overflow',
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

    expect(find.text('收藏详情'), findsOneWidget);
    // 回归测试：防止窄屏下收藏详情溢出。
    // takeException() 仅捕获当帧异常，若 Flutter 溢出处理机制变更需更新。
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites detail delete removes favorite and returns to list', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-to-delete',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-to-delete',
          userMessageContent: '要删除的问题',
          assistantContent: '要删除的回复',
        );
      },
    );

    expect(find.text('收藏详情'), findsOneWidget);

    await tester.tap(find.byTooltip('删除收藏').first);
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    // 确认对话框与详情页路由出场叠在一起，一次等完
    await settleRouteTransition(tester);

    expect(find.text('收藏详情'), findsNothing);
    // 删除后返回收藏总览网格，系统未分类卡片仍在。
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('favorites detail shows reasoning content when present', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-reasoning',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-reasoning',
          userMessageContent: '有推理的问题',
          assistantContent: '有推理的回复',
          assistantReasoningContent: '这是深度思考的推理过程',
        );
      },
    );

    expect(find.text('深度思考'), findsOneWidget);

    await tester.tap(find.text('展开'));
    // 推理内容展开是 AnimatedSize 动画
    await settleAnimatedWidgetTransition(tester);

    expect(find.text('这是深度思考的推理过程'), findsOneWidget);
  });

  testWidgets('favorites detail shows move button for uncategorized favorite', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-uncategorized',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-uncategorized',
          userMessageContent: '未分类的收藏问题',
          assistantContent: '未分类的回复',
        );
        seedCollection(db, id: 'col-1', name: '技术收藏');
      },
    );

    expect(find.text('未分类'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.drive_file_move_outline));
    await settleOverlayTransition(tester);

    expect(find.text('移动到收藏夹'), findsOneWidget);
    expect(find.text('未分类'), findsWidgets);
    expect(find.text('技术收藏'), findsOneWidget);
  });

  testWidgets('favorites detail hides reasoning panel when absent', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      initialLocation: '/favorites/items/fav-no-reasoning',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-no-reasoning',
          userMessageContent: '无推理的问题',
          assistantContent: '无推理的回复',
          assistantReasoningContent: '',
        );
      },
    );

    expect(find.text('无推理的回复'), findsOneWidget);
    expect(find.text('深度思考'), findsNothing);
    expect(find.text('展开'), findsNothing);
  });
}
