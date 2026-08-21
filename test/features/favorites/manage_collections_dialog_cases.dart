import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

void registerManageCollectionsDialogTests() {
  testWidgets('管理对话框始终显示系统未分类收藏夹且不提供操作', (tester) async {
    await setUpFavoritesScreen(tester);

    await tester.tap(find.byTooltip('管理收藏夹'));
    await settleOverlayTransition(tester);

    expect(find.text('管理收藏夹'), findsOneWidget);
    // 系统收藏夹恒存在：显示身份标识，不提供重命名/删除入口。
    // "未分类"同时出现在页面筛选 chip 与对话框条目中，用 findsWidgets。
    expect(find.text('未分类'), findsWidgets);
    expect(find.text('系统收藏夹'), findsOneWidget);
    expect(find.byTooltip('重命名'), findsNothing);
    expect(find.byTooltip('删除收藏夹（内部收藏移入未分类）'), findsNothing);
  });

  testWidgets('manage collections dialog renames collection', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '旧名称');
      },
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.byTooltip('重命名'));
    // 行内编辑态切换是 setState，单帧即可
    await tester.pump();

    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.byTooltip('确认重命名'));
    // 重命名 Future 完成后行内编辑态退出
    await tester.pump();

    expect(find.text('新名称'), findsWidgets);
    expect(find.text('旧名称'), findsNothing);
  });

  testWidgets(
    'manage collections dialog deletes collection after confirmation',
    (tester) async {
      await setUpFavoritesScreen(
        tester,
        seed: (db) {
          seedCollection(db, id: 'col-1', name: '要删除的收藏夹');
        },
      );

      await tester.tap(find.byTooltip('管理收藏夹'));
      await settleOverlayTransition(tester);

      await tester.tap(find.byTooltip('删除收藏夹（内部收藏移入未分类）'));
      await settleOverlayTransition(tester);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      // 确认对话框出场，删除 Future 随帧完成
      await settleOverlayTransition(tester);

      expect(find.text('要删除的收藏夹'), findsNothing);
      // 系统未分类收藏夹始终保留（筛选 chip 与对话框条目各一处）。
      expect(find.text('未分类'), findsWidgets);
    },
  );

  testWidgets('manage collections dialog cancel delete keeps collection', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '保留的收藏夹');
      },
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.byTooltip('删除收藏夹（内部收藏移入未分类）'));
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await settleOverlayTransition(tester);

    // Collection name still present in both filter chip and dialog.
    expect(find.text('保留的收藏夹'), findsWidgets);
  });

  testWidgets('manage collections dialog cancel rename keeps original name', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '原名');
      },
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.byTooltip('重命名'));
    // 行内编辑态切换是 setState，单帧即可
    await tester.pump();

    await tester.enterText(find.byType(TextField), '不应生效的名称');
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();

    expect(find.text('原名'), findsWidgets);
    expect(find.text('不应生效的名称'), findsNothing);
  });

  testWidgets('manage collections dialog empty rename is ignored', (
    tester,
  ) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-1', name: '现有名称');
      },
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await settleOverlayTransition(tester);

    await tester.tap(find.byTooltip('重命名'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('确认重命名'));
    // 空名不触发重命名，只退出行内编辑态
    await tester.pump();

    expect(find.text('现有名称'), findsWidgets);
  });
}
