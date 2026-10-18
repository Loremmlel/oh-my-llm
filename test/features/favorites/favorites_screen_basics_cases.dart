import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_tile.dart';

import 'favorites_screen_test_helpers.dart';

void registerFavoritesScreenBasicsTests() {
  testWidgets('空库仍显示置顶的系统未分类收藏夹卡片', (tester) async {
    await setUpFavoritesScreen(tester);

    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.text('0 项收藏'), findsOneWidget);
  });

  testWidgets('新建收藏夹拒绝保留名，取消不创建，重开保存后可按 Enter 打开', (tester) async {
    await setUpFavoritesScreen(tester);
    final router = GoRouter.of(
      tester.element(find.byType(FavoriteCollectionTile)),
    );

    await tester.tap(find.byTooltip('新建收藏夹'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '未分类');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pump();
    expect(find.text('该名称被系统收藏夹保留'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('未分类'), findsOneWidget);
    await tester.tap(find.byTooltip('新建收藏夹'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '旅行计划');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    // 新卡片出现在总览中，且没有自动打开空收藏夹。
    expect(find.text('旅行计划'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/favorites',
    );

    // 键盘等价操作：Enter 打开聚焦的卡片。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      startsWith('/favorites/collections/'),
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('旅行计划')),
      findsOneWidget,
    );
  });
}
