import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_collection_items_screen.dart';
import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_card.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 深链直达指定收藏的详情页。
Future<void> _openDetail(
  WidgetTester tester,
  String favoriteId, {
  Size viewportSize = const Size(1440, 1200),
  void Function(AppDatabase database)? seed,
}) {
  return setUpFavoritesScreen(
    tester,
    viewportSize: viewportSize,
    initialLocation: '/favorites/items/$favoriteId',
    seed: seed,
  );
}

/// 从 AppBar 溢出菜单执行菜单项。
Future<void> _runOverflowAction(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await settleOverlayTransition(tester);
  await tester.tap(find.text(label));
  await settleOverlayTransition(tester);
}

void registerFavoriteDetailScreenTests() {
  testWidgets('详情页展示标题、所属收藏夹、模型与收藏时间元数据', (tester) async {
    await _openDetail(
      tester,
      'fav-meta',
      seed: (db) {
        // 先建收藏夹再放收藏，满足 favorites.collection_id 外键约束。
        seedCollection(db, id: 'col-meta', name: '技术收藏');
        seedFavorite(
          db,
          id: 'fav-meta',
          title: '自定义标题',
          userMessageContent: '元数据问题',
          assistantContent: '元数据回复',
          assistantModelDisplayName: 'DeepSeek V4 Flash',
          collectionId: 'col-meta',
          createdAt: DateTime(2026, 4, 28),
        );
      },
    );

    expect(find.text('自定义标题'), findsOneWidget);
    expect(find.text('技术收藏'), findsOneWidget);
    expect(find.text('DeepSeek V4 Flash'), findsOneWidget);
    expect(find.text(formatDateTime(DateTime(2026, 4, 28))), findsOneWidget);
  });

  testWidgets('查看来源对话主操作跳转到聊天页', (tester) async {
    await _openDetail(
      tester,
      'fav-with-source',
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

    // 主操作按钮可见，来源标题作为元信息一并展示。
    expect(find.widgetWithText(FilledButton, '查看来源对话'), findsOneWidget);
    expect(find.text('原始对话'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.widgetWithText(FilledButton, '查看来源对话')),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查看来源对话'));
    await settleRouteTransition(tester);

    // 生产路由下聊天页是真实 ChatScreen，用路由位置断言跳转成功。
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      AppDestination.chat.path,
    );
  });

  testWidgets('来源缺失时查看来源对话禁用并显示恢复文案', (tester) async {
    await _openDetail(
      tester,
      'fav-no-source',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-no-source',
          userMessageContent: '无来源的问题',
          assistantContent: '无来源的回复',
        );
      },
    );

    final buttonFinder = find.widgetWithText(FilledButton, '查看来源对话');
    expect(buttonFinder, findsOneWidget);
    // 来源缺失：按钮禁用且给出明确恢复文案，而不是隐藏入口。
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
    expect(find.text('这条收藏没有关联的来源对话。'), findsOneWidget);
  });

  testWidgets('重命名、移动与删除操作收进溢出菜单', (tester) async {
    await _openDetail(
      tester,
      'fav-overflow',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-overflow',
          userMessageContent: '溢出菜单问题',
          assistantContent: '溢出菜单回复',
        );
      },
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await settleOverlayTransition(tester);

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('移动到收藏夹'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    // 平铺的删除图标按钮不再出现在页面上。
    expect(find.byTooltip('删除收藏'), findsNothing);
  });

  testWidgets('溢出菜单删除需确认且确认后返回收藏总览', (tester) async {
    await _openDetail(
      tester,
      'fav-to-delete',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-to-delete',
          userMessageContent: '要删除的问题',
          assistantContent: '要删除的回复',
        );
      },
    );

    await _runOverflowAction(tester, '删除');

    // 确认对话框先出现，取消时不删除。
    expect(find.text('确定要删除这条收藏记录吗？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);
    expect(find.text('要删除的回复'), findsOneWidget);

    await _runOverflowAction(tester, '删除');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await settleRouteTransition(tester);

    expect(find.text('要删除的回复'), findsNothing);
    // 删除后返回收藏总览网格，系统未分类卡片仍在。
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('移动成功后留在详情页且所属收藏夹更新为目标夹', (tester) async {
    await _openDetail(
      tester,
      'fav-to-move',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-to-move',
          userMessageContent: '待移动的问题',
          assistantContent: '待移动的回复',
        );
        seedCollection(db, id: 'col-target', name: '归档夹');
      },
    );

    await _runOverflowAction(tester, '移动到收藏夹');
    await tester.tap(find.text('归档夹'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '移动'),
      ),
    );
    await settleRouteTransition(tester);

    // 移动后停留在详情页，收藏夹入口实时更新为目标夹。
    expect(find.text('待移动的回复'), findsOneWidget);
    expect(find.text('归档夹'), findsOneWidget);
  });

  testWidgets('点击所属收藏夹入口跳转到对应收藏夹列表页', (tester) async {
    await _openDetail(
      tester,
      'fav-in-collection',
      seed: (db) {
        seedCollection(db, id: 'col-target', name: '归档夹');
        seedFavorite(
          db,
          id: 'fav-in-collection',
          userMessageContent: '归属明确的问题',
          assistantContent: '归属明确的回复',
          collectionId: 'col-target',
        );
      },
    );

    await tester.tap(find.text('归档夹'));
    await settleRouteTransition(tester);

    expect(find.byType(FavoriteCollectionItemsScreen), findsOneWidget);
  });

  testWidgets('宽屏详情内容限宽可读宽度', (tester) async {
    await _openDetail(
      tester,
      'fav-wide',
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-wide',
          userMessageContent: '宽屏问题',
          assistantContent: '宽屏回复',
        );
      },
    );

    expect(
      tester.getSize(find.byType(FavoriteCard)).width,
      lessThanOrEqualTo(AppContentWidths.readable),
    );
  });

  testWidgets('窄屏详情内容占满父宽且无溢出', (tester) async {
    await _openDetail(
      tester,
      'fav-mobile-overflow',
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

    // 回归测试：防止窄屏下收藏详情溢出。
    // takeException() 仅捕获当帧异常，若 Flutter 溢出处理机制变更需更新。
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FavoriteCard)).width,
      lessThanOrEqualTo(390),
    );
  });

  testWidgets('详情页展示用户消息与模型回复内容', (tester) async {
    await _openDetail(
      tester,
      'fav-detail',
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

    expect(find.text('这是完整的用户消息内容，用于详情测试'), findsOneWidget);
    expect(find.textContaining('这是完整的模型回复内容'), findsOneWidget);
  });

  testWidgets('有推理内容时展示可展开的推理面板', (tester) async {
    await _openDetail(
      tester,
      'fav-reasoning',
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

  testWidgets('无推理内容时不展示推理面板', (tester) async {
    await _openDetail(
      tester,
      'fav-no-reasoning',
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
