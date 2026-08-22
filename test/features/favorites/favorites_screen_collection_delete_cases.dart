import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection_delete_request.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_collection_summary.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 按需抛出删除失败的收藏夹仓库装饰器，用于模拟事务故障。
class _FlakyCollectionsRepository implements CollectionsRepository {
  _FlakyCollectionsRepository(this._inner);

  final CollectionsRepository _inner;

  /// 置 true 时 delete 抛出异常。
  bool failDelete = false;

  @override
  List<FavoriteCollectionSummary> loadSummaries() => _inner.loadSummaries();

  @override
  List<FavoriteCollection> loadAll() => _inner.loadAll();

  @override
  void save(FavoriteCollection collection) => _inner.save(collection);

  @override
  int delete(
    String collectionId, {
    required CollectionDeleteRequest disposition,
  }) {
    if (failDelete) throw StateError('注入的删除事务失败');
    return _inner.delete(collectionId, disposition: disposition);
  }
}

/// 打开含 [itemCount] 条收藏的普通收藏夹列表页。
Future<void> _openCollection(
  WidgetTester tester, {
  required int itemCount,
  String collectionId = 'col-target',
  String collectionName = '待删夹',
  void Function(AppDatabase database)? extraSeed,
}) async {
  await setUpFavoritesScreen(
    tester,
    seed: (db) {
      seedCollection(db, id: collectionId, name: collectionName);
      seedFavoriteItems(db, collectionId: collectionId, count: itemCount);
      extraSeed?.call(db);
    },
    initialLocation: '/favorites/collections/$collectionId',
  );
}

/// 从 AppBar 打开"删除收藏夹"对话框。
Future<void> _openDeleteDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('删除收藏夹'));
  await settleOverlayTransition(tester);
}

void registerFavoritesScreenCollectionDeleteTests() {
  testWidgets('删除非空收藏夹对话框显示准确数量', (tester) async {
    await _openCollection(tester, itemCount: 3);

    await _openDeleteDialog(tester);

    expect(find.textContaining('3'), findsWidgets);
    // 默认去向是移动到系统未分类。
    expect(find.textContaining('移入'), findsOneWidget);
  });

  testWidgets('默认移动到系统未分类且确认后收藏保留', (tester) async {
    await _openCollection(tester, itemCount: 2);

    await _openDeleteDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await settleRouteTransition(tester);

    // 收藏夹消失后回退系统未分类，两条收藏仍在（归属系统夹）。
    expect(find.text('待删夹'), findsNothing);
    expect(find.textContaining('共 2 条 · 1/1 页'), findsOneWidget);
  });

  testWidgets('可选择其他普通收藏夹作为移动去向', (tester) async {
    await _openCollection(
      tester,
      itemCount: 1,
      extraSeed: (db) => seedCollection(db, id: 'col-alt', name: '备用夹'),
    );

    await _openDeleteDialog(tester);
    await tester.tap(find.text('备用夹'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await settleRouteTransition(tester);

    expect(find.text('待删夹'), findsNothing);
    // 去总览验证收藏已进入备用夹——通过备用夹页面验证更直接。
    final router = GoRouter.of(tester.element(find.text('未分类')));
    router.go('/favorites');
    await settleRouteTransition(tester);
    await tester.tap(find.text('备用夹'));
    await settleRouteTransition(tester);
    expect(find.textContaining('问题001'), findsOneWidget);
  });

  testWidgets('危险选项连同收藏一并删除', (tester) async {
    await _openCollection(tester, itemCount: 2);

    await _openDeleteDialog(tester);
    // 次级危险选项：连同收藏一并删除。
    await tester.tap(find.textContaining('及其中'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await settleRouteTransition(tester);

    expect(find.text('待删夹'), findsNothing);
    expect(find.textContaining('共 0 条 · 0/0 页'), findsNothing);
    expect(find.textContaining('暂无收藏'), findsOneWidget);
  });

  testWidgets('移动去向不包含待删除的收藏夹自身', (tester) async {
    await _openCollection(
      tester,
      itemCount: 1,
      extraSeed: (db) => seedCollection(db, id: 'col-alt', name: '备用夹'),
    );

    await _openDeleteDialog(tester);

    // 对话框内"待删夹"不作为可选去向出现；只有系统夹与备用夹。
    expect(find.widgetWithText(RadioListTile<String>, '待删夹'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('备用夹'), findsOneWidget);
  });

  testWidgets('移动去向列表渲染在移入选项与危险删除选项之间', (tester) async {
    await _openCollection(tester, itemCount: 2);

    await _openDeleteDialog(tester);

    // 顺序契约：去向单选列表在视觉上归属「移入其他收藏夹」选项，必须
    // 渲染在它与危险删除选项之间；挂在删除选项之后会让用户误以为去向
    // 从属于删除。widgetList 按树序遍历，与 Column 子项视觉顺序一致。
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .toList();
    final moveIndex = texts.indexOf('移入其他收藏夹');
    final targetIndex = texts.indexOf('未分类');
    final deleteIndex = texts.indexWhere((text) => text.contains('及其中'));
    expect(moveIndex, greaterThanOrEqualTo(0));
    expect(targetIndex, greaterThan(moveIndex));
    expect(deleteIndex, greaterThan(targetIndex));
  });

  testWidgets('对话框内新建收藏夹只选中仍需最终确认', (tester) async {
    await _openCollection(tester, itemCount: 1);

    await _openDeleteDialog(tester);

    await tester.tap(find.text('新建收藏夹作为去向'));
    await settleOverlayTransition(tester);
    // 分页栏的页码输入框也是 TextField，限定在对话框内输入。
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新建去向',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settleOverlayTransition(tester);

    // 新夹被选中但删除尚未提交：确认按钮仍在等待最终确认。
    expect(find.text('新建去向'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '删除收藏夹'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await settleRouteTransition(tester);

    expect(find.text('待删夹'), findsNothing);
  });

  testWidgets('删除事务失败时对话框保持打开并内联报错', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedCollection(db, id: 'col-flaky', name: '事务失败夹');
    seedFavoriteItems(db, collectionId: 'col-flaky', count: 1);
    final flaky = _FlakyCollectionsRepository(SqliteCollectionsRepository(db));
    final preferences = await createEmptyPreferences(db);

    await repumpFavoritesScreen(
      tester,
      preferences: preferences,
      database: db,
      initialLocation: '/favorites/collections/col-flaky',
      extraOverrides: [collectionsRepositoryProvider.overrideWithValue(flaky)],
      // 排除生产绑定，让故障注入装饰器接管收藏夹仓库。
      bindFavoritesRepositories: false,
    );

    flaky.failDelete = true;
    await tester.tap(find.byTooltip('删除收藏夹'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await tester.pump();

    // 事务失败：对话框保持打开并内联提示。
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);

    flaky.failDelete = false;
    await tester.tap(find.widgetWithText(FilledButton, '删除收藏夹'));
    await settleRouteTransition(tester);

    // 重试成功后当前浏览的收藏夹被删除，浏览器回退系统未分类；
    // 系统夹此时为空，展示夹内空状态。
    expect(find.textContaining('暂无收藏'), findsOneWidget);
    expect(find.text('事务失败夹'), findsNothing);
  });
}
