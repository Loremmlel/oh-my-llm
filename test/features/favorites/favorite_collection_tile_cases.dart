import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/presentation/widgets/favorite_collection_tile.dart';

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
  await tester.pumpAndSettle();
}

void registerFavoriteCollectionTileTests() {
  testWidgets('收藏夹重命名拒绝保留名，修正后卡片更新', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '旧名称');
      },
    );

    await _openTileMenu(tester, '旧名称');
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    // 对话框预填原名称。
    expect(find.text('旧名称'), findsWidgets);
    await tester.enterText(find.byType(TextField), '未分类');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('该名称被系统收藏夹保留'), findsOneWidget);
    expect(find.text('旧名称'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新名称'), findsOneWidget);
    expect(find.text('旧名称'), findsNothing);
  });

  testWidgets('空收藏夹删除取消后保留，再确认后卡片消失', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-gone', name: '待删除的收藏夹');
      },
    );

    await _openTileMenu(tester, '待删除的收藏夹');
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除收藏夹'), findsOneWidget);
    await tester.tap(find.text('删除收藏夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('待删除的收藏夹'), findsOneWidget);

    await _openTileMenu(tester, '待删除的收藏夹');
    await tester.tap(find.text('删除收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('待删除的收藏夹'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
  });
}
