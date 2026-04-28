import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/favorites/presentation/widgets/dialogs/manage_collections_dialog.dart';

import '../../test_database.dart';
import 'favorites_screen_test_helpers.dart';

void registerManageCollectionsDialogTests() {
  testWidgets('manage collections dialog shows empty state', (tester) async {
    final preferences = await createEmptyPreferences();

    await pumpFavoritesScreen(tester, preferences: preferences);

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    expect(find.byType(ManageCollectionsDialog), findsOneWidget);
    expect(find.text('暂无收藏夹。收藏回复时可创建。'), findsOneWidget);
  });

  testWidgets('manage collections dialog lists existing collections', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedCollection(database, id: 'col-1', name: '工作笔记');
    seedCollection(database, id: 'col-2', name: '学习资料');

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    // Collection names appear in both the filter chip bar and the dialog list.
    expect(find.text('工作笔记'), findsWidgets);
    expect(find.text('学习资料'), findsWidgets);
  });

  testWidgets('manage collections dialog renames collection', (tester) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedCollection(database, id: 'col-1', name: '旧名称');

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(ManageCollectionsDialog),
        matching: find.byType(TextField),
      ),
      '新名称',
    );
    await tester.tap(find.byTooltip('确认重命名'));
    await tester.pumpAndSettle();

    expect(find.text('新名称'), findsWidgets);
    expect(find.text('旧名称'), findsNothing);
  });

  testWidgets('manage collections dialog deletes collection after confirmation', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedCollection(database, id: 'col-1', name: '要删除的收藏夹');

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

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
    final preferences = await createEmptyPreferences();
    final database = await createTestDatabase(preferences);

    seedCollection(database, id: 'col-1', name: '保留的收藏夹');

    await pumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: database,
    );

    await tester.tap(find.byTooltip('管理收藏夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除收藏夹（内部收藏移入未分类）'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    // Collection name still present in both filter chip and dialog.
    expect(find.text('保留的收藏夹'), findsWidgets);
  });
}
