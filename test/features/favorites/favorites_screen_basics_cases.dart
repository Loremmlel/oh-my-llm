import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_screen_test_helpers.dart';

void registerFavoritesScreenBasicsTests() {
  testWidgets('favorites screen shows empty state message', (tester) async {
    await setUpFavoritesScreen(tester);

    expect(
      find.text('暂无收藏'),
      findsOneWidget,
    );
  });

  testWidgets('favorites screen renders favorites list items', (tester) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(db, id: 'fav-1', userMessageContent: '这是用户问题', assistantContent: '这是模型回复');
    });

    expect(find.text('这是用户问题'), findsOneWidget);
    expect(find.text('这是模型回复'), findsOneWidget);
  });

  testWidgets('favorites screen uncategorized filter shows correct items', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(db, id: 'fav-1', userMessageContent: '未分类问题', assistantContent: '未分类回复', collectionId: null);
    });

    await tester.tap(find.widgetWithText(FilterChip, '未分类'));
    await tester.pumpAndSettle();

    expect(find.text('未分类问题'), findsOneWidget);
    expect(find.text('未分类回复'), findsOneWidget);
  });

  testWidgets('favorites screen shows empty hint for empty filters', (tester) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '我的收藏夹');
    });

    await tester.tap(find.widgetWithText(FilterChip, '我的收藏夹'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无收藏'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '未分类'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('favorites screen tapping item navigates to detail', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedFavorite(db, id: 'fav-1', userMessageContent: '导航测试问题', assistantContent: '导航测试回复');
    });

    await tester.tap(find.text('导航测试问题'));
    await tester.pumpAndSettle();

    expect(find.text('收藏详情'), findsOneWidget);
  });

  testWidgets('favorites screen 全部 filter shows all items', (tester) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '我的收藏夹');
      seedFavorite(db, id: 'fav-1', userMessageContent: '分类问题', assistantContent: '分类回复', collectionId: 'col-1');
      seedFavorite(db, id: 'fav-2', userMessageContent: '未分类问题', assistantContent: '未分类回复', collectionId: null);
    });

    // "全部" 是默认选中状态，应显示所有收藏
    expect(find.text('分类问题'), findsOneWidget);
    expect(find.text('未分类问题'), findsOneWidget);
  });

  testWidgets('favorites screen collection filter shows correct items', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '技术笔记');
      seedFavorite(db, id: 'fav-1', userMessageContent: '技术问题', assistantContent: '技术回复', collectionId: 'col-1');
      seedFavorite(db, id: 'fav-2', userMessageContent: '其他问题', assistantContent: '其他回复', collectionId: null);
    });

    await tester.tap(find.widgetWithText(FilterChip, '技术笔记'));
    await tester.pumpAndSettle();

    expect(find.text('技术问题'), findsOneWidget);
    expect(find.text('其他问题'), findsNothing);
  });
}
