import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_screen_test_helpers.dart';

void registerManageCollectionsDialogTests() {
  testWidgets('manage collections dialog shows empty state', (tester) async {
    await setUpFavoritesScreen(tester);

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    expect(find.text('管理收藏夹'), findsOneWidget);
    expect(find.text('暂无收藏夹。收藏回复时可创建。'), findsOneWidget);
  });

  testWidgets('manage collections dialog renames collection', (tester) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '旧名称');
    });

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.byTooltip('确认重命名'));
    await tester.pumpAndSettle();

    expect(find.text('新名称'), findsWidgets);
    expect(find.text('旧名称'), findsNothing);
  });

  testWidgets('manage collections dialog deletes collection after confirmation', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '要删除的收藏夹');
    });

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除收藏夹（内部收藏移入未分类）'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('要删除的收藏夹'), findsNothing);
    expect(find.text('暂无收藏夹。收藏回复时可创建。'), findsOneWidget);
  });

  testWidgets('manage collections dialog cancel delete keeps collection', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '保留的收藏夹');
    });

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除收藏夹（内部收藏移入未分类）'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    // Collection name still present in both filter chip and dialog.
    expect(find.text('保留的收藏夹'), findsWidgets);
  });

  testWidgets('manage collections dialog cancel rename keeps original name', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '原名');
    });

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '不应生效的名称');
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();

    expect(find.text('原名'), findsWidgets);
    expect(find.text('不应生效的名称'), findsNothing);
  });

  testWidgets('manage collections dialog empty rename is ignored', (
    tester,
  ) async {
    await setUpFavoritesScreen(tester, seed: (db) {
      seedCollection(db, id: 'col-1', name: '现有名称');
    });

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('确认重命名'));
    await tester.pumpAndSettle();

    expect(find.text('现有名称'), findsWidgets);
  });
}
