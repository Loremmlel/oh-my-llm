import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_tile.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 定位指定名称收藏夹的卡片。
Finder _tileOf(String name) {
  return find.ancestor(
    of: find.text(name),
    matching: find.byType(FavoriteCollectionTile),
  );
}

/// 打开指定名称收藏夹卡片的溢出菜单。
Future<void> _openTileMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: _tileOf(name), matching: find.byIcon(Icons.more_vert)),
  );
  await settleOverlayTransition(tester);
}

void registerFavoriteCollectionTileTests() {
  testWidgets('系统收藏夹卡片不提供任何管理操作', (tester) async {
    await setUpFavoritesScreen(tester);

    final systemTile = _tileOf('未分类');
    expect(systemTile, findsOneWidget);
    expect(
      find.descendant(of: systemTile, matching: find.byIcon(Icons.more_vert)),
      findsNothing,
    );
  });

  testWidgets('普通空收藏夹菜单提供重命名与删除入口', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-empty', name: '工作笔记');
      },
    );

    await _openTileMenu(tester, '工作笔记');

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除收藏夹'), findsOneWidget);
  });

  testWidgets('非空普通收藏夹菜单暂不提供删除入口', (tester) async {
    // 非空收藏夹的删除需要选择内容去向，由收藏夹内列表页承接，
    // 总览卡片菜单只保留无级联歧义的空夹删除。
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-full', name: '技术积累');
        seedFavorite(
          db,
          id: 'fav-in-col',
          userMessageContent: '技术问题',
          assistantContent: '技术回复',
          collectionId: 'col-full',
        );
      },
    );

    await _openTileMenu(tester, '技术积累');

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除收藏夹'), findsNothing);
  });

  testWidgets('菜单重命名收藏夹后卡片更新名称', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '旧名称');
      },
    );

    await _openTileMenu(tester, '旧名称');
    await tester.tap(find.text('重命名'));
    await settleOverlayTransition(tester);

    // 对话框预填原名称。
    expect(find.text('旧名称'), findsWidgets);
    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settleOverlayTransition(tester);

    expect(find.text('新名称'), findsOneWidget);
    expect(find.text('旧名称'), findsNothing);
  });

  testWidgets('重命名使用系统保留名时内联报错且不生效', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '现有名称');
      },
    );

    await _openTileMenu(tester, '现有名称');
    await tester.tap(find.text('重命名'));
    await settleOverlayTransition(tester);

    await tester.enterText(find.byType(TextField), '未分类');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('该名称被系统收藏夹保留'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    expect(find.text('现有名称'), findsOneWidget);
  });

  testWidgets('删除空收藏夹需确认且成功后卡片消失', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-gone', name: '待删除的收藏夹');
      },
    );

    await _openTileMenu(tester, '待删除的收藏夹');
    await tester.tap(find.text('删除收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settleOverlayTransition(tester);

    expect(find.text('待删除的收藏夹'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
  });

  testWidgets('取消删除保留空收藏夹', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-keep', name: '保留的收藏夹');
      },
    );

    await _openTileMenu(tester, '保留的收藏夹');
    await tester.tap(find.text('删除收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    expect(find.text('保留的收藏夹'), findsOneWidget);
  });
}
