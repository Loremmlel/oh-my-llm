import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_tile.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 从当前键盘焦点向上查找所属的收藏夹卡片，返回其收藏夹名称；
/// 焦点不在任何卡片内时返回 null。
String? _focusedCollectionName() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final state = context
      .findAncestorStateOfType<State<FavoriteCollectionTile>>();
  final tile = state?.widget;
  if (tile is! FavoriteCollectionTile) return null;
  return tile.summary.collection.name;
}

void registerFavoritesScreenBasicsTests() {
  testWidgets('空库仍显示置顶的系统未分类收藏夹卡片', (tester) async {
    await setUpFavoritesScreen(tester);

    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.text('0 项收藏'), findsOneWidget);
  });

  testWidgets('收藏夹卡片显示名称、数量与最近收录时间', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(
          db,
          id: 'col-travel',
          name: '旅行足迹',
          createdAt: DateTime(2026, 4, 1),
        );
        seedFavorite(
          db,
          id: 'fav-in-travel',
          userMessageContent: '旅行问题',
          assistantContent: '旅行回复',
          collectionId: 'col-travel',
          collectionAssignedAt: DateTime(2026, 5, 10, 8, 30),
        );
      },
    );

    expect(find.text('旅行足迹'), findsOneWidget);
    expect(find.text('1 项收藏'), findsOneWidget);
    // 最近收录时间来自归属时间聚合，而非收藏夹创建时间。
    expect(find.text('2026-05-10'), findsOneWidget);
    expect(find.text('2026-04-01'), findsNothing);
  });

  testWidgets('空收藏夹卡片回退显示创建时间', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(
          db,
          id: 'col-empty',
          name: '空空如也',
          createdAt: DateTime(2026, 4, 1),
        );
      },
    );

    // 系统夹同样为空，"0 项收藏"在两张卡片上出现。
    expect(find.text('0 项收藏'), findsWidgets);
    expect(find.text('2026-04-01'), findsOneWidget);
  });

  testWidgets('超长收藏夹名称提供完整名称提示', (tester) async {
    const longName = '这是一个非常非常非常长的收藏夹名称用于验证溢出时的完整名称提示';
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-long', name: longName);
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip(longName), findsOneWidget);
  });

  testWidgets('点击系统收藏夹卡片进入对应收藏夹路由', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedFavorite(
          db,
          id: 'fav-sys',
          userMessageContent: '系统夹内的问题',
          assistantContent: '系统夹内的回复',
        );
      },
    );
    final router = GoRouter.of(
      tester.element(find.byType(FavoriteCollectionTile)),
    );

    await tester.tap(find.text('未分类'));
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites/collections/__uncategorized_favorites__',
    );
  });

  testWidgets('新建收藏夹后新卡获得焦点、支持 Enter 打开且不自动跳转', (tester) async {
    await setUpFavoritesScreen(tester);
    final router = GoRouter.of(
      tester.element(find.byType(FavoriteCollectionTile)),
    );

    await tester.tap(find.byTooltip('新建收藏夹'));
    await settleOverlayTransition(tester);

    await tester.enterText(find.byType(TextField), '旅行计划');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settleOverlayTransition(tester);

    // 新卡片出现在总览中，且没有自动打开空收藏夹。
    expect(find.text('旅行计划'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites',
    );
    // 新建卡片持有可见焦点，保证键盘用户可继续操作。
    expect(_focusedCollectionName(), '旅行计划');

    // 键盘等价操作：Enter 打开聚焦的卡片。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleRouteTransition(tester);

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      startsWith('/favorites/collections/'),
    );
  });

  testWidgets('新建时使用系统保留名在对话框内联报错且不创建', (tester) async {
    await setUpFavoritesScreen(tester);

    await tester.tap(find.byTooltip('新建收藏夹'));
    await settleOverlayTransition(tester);

    await tester.enterText(find.byType(TextField), '未分类');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pump();

    expect(find.text('该名称被系统收藏夹保留'), findsOneWidget);
    // 对话框保持打开，等待修改名称。
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    // 未创建同名普通夹："未分类"仍只有系统夹一处。
    expect(find.text('未分类'), findsOneWidget);
  });
}
