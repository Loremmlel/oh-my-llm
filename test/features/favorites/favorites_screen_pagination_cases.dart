import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_bar.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_page.dart';
import 'package:oh_my_llm/features/favorites/presentation/favorite_collection_items_screen.dart';

import '../../helpers/async/widget_test_animation.dart';
import 'favorites_screen_test_helpers.dart';

/// 按需抛出查询失败的收藏仓库装饰器，用于模拟存储层故障。
class _FlakyFavoritesRepository implements FavoritesRepository {
  _FlakyFavoritesRepository(this._inner);

  final FavoritesRepository _inner;

  /// 置 true 时 loadPage 抛出异常。
  bool failLoadPage = false;

  void _guard() {
    if (failLoadPage) throw StateError('注入的查询失败');
  }

  @override
  FavoritePage loadPage({
    required String collectionId,
    required int limit,
    required int offset,
  }) {
    _guard();
    return _inner.loadPage(
      collectionId: collectionId,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Favorite? loadById(String id) => _inner.loadById(id);

  @override
  Favorite? findByAssistantContent(String assistantContent) =>
      _inner.findByAssistantContent(assistantContent);

  @override
  Set<String> loadFavoritedAssistantContents(
    Iterable<String> assistantContents,
  ) => _inner.loadFavoritedAssistantContents(assistantContents);

  @override
  void save(Favorite favorite) => _inner.save(favorite);

  @override
  int deleteMany(Set<String> ids) => _inner.deleteMany(ids);

  @override
  int moveMany(
    Set<String> ids, {
    required String targetCollectionId,
    required DateTime assignedAt,
  }) => _inner.moveMany(
    ids,
    targetCollectionId: targetCollectionId,
    assignedAt: assignedAt,
  );

  @override
  void updateTitle(String id, String? title) => _inner.updateTitle(id, title);
}

/// 打开系统未分类收藏夹的分页列表页。
Future<AppDatabase> _openSystemCollection(
  WidgetTester tester, {
  String query = '',
  required int itemCount,
  Size viewportSize = const Size(1440, 1200),
}) {
  return setUpFavoritesScreen(
    tester,
    viewportSize: viewportSize,
    seed: (db) => seedFavoriteItems(
      db,
      collectionId: '__uncategorized_favorites__',
      count: itemCount,
    ),
    initialLocation: '/favorites/collections/__uncategorized_favorites__$query',
  );
}

void registerFavoritesScreenPaginationTests() {
  testWidgets('翻到第 2 页显示剩余条目并把页码写入 URL', (tester) async {
    await _openSystemCollection(tester, itemCount: 21, query: '?pageSize=20');
    final router = GoRouter.of(
      tester.element(find.byType(FavoriteCollectionItemsScreen)),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AppPaginationBar),
        matching: find.text('2'),
      ),
    );
    await settleRouteTransition(tester);

    expect(find.text('问题001'), findsOneWidget);
    expect(find.text('问题021'), findsNothing);
    expect(find.textContaining('共 21 条 · 2/2 页'), findsOneWidget);
    expect(router.routerDelegate.state.uri.queryParameters['page'], '2');
  });

  testWidgets('切换容量持久化并写入 URL，重挂后仍生效', (tester) async {
    final db = await _openSystemCollection(
      tester,
      itemCount: 25,
      query: '?pageSize=20',
    );

    // 打开"每页"容量下拉并切换为 50；dropdown 菜单里选项文本为纯数字，
    // 用 descendant 限定在分页栏内避免与列表内容混淆。
    await tester.tap(find.text('20').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('50').last);
    await settleRouteTransition(tester);

    expect(find.textContaining('共 25 条 · 1/1 页'), findsOneWidget);

    // 容量偏好已持久化：复用同一偏好实例重挂后仍为每页 50。
    final prefs = await createEmptyPreferences(db);
    await repumpFavoritesScreen(
      tester,
      preferences: prefs,
      database: db,
      initialLocation: '/favorites/collections/__uncategorized_favorites__',
    );
    expect(find.textContaining('共 25 条 · 1/1 页'), findsOneWidget);
  });

  testWidgets('进入详情返回后恢复当前页窗口', (tester) async {
    await _openSystemCollection(tester, itemCount: 21, query: '?page=2');

    await tester.tap(find.text('问题001'));
    await settleRouteTransition(tester);
    expect(find.text('收藏详情'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settleRouteTransition(tester);

    // 返回原夹时窗口保持第 2 页，不重置回第 1 页。
    expect(find.textContaining('共 21 条 · 2/2 页'), findsOneWidget);
    expect(find.text('问题001'), findsOneWidget);
  });

  testWidgets('末页唯一条目被删除后自动回退前一页', (tester) async {
    await _openSystemCollection(tester, itemCount: 21, query: '?page=2');
    final router = GoRouter.of(
      tester.element(find.byType(FavoriteCollectionItemsScreen)),
    );

    // 第 2 页只有 fav-001：经行内溢出菜单删除并确认。
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('删除'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settleRouteTransition(tester);

    // 总数回到 20，页码从越界的第 2 页归一回最后一页（现在是第 1 页）。
    expect(find.textContaining('共 20 条 · 1/1 页'), findsOneWidget);
    expect(find.text('问题020'), findsOneWidget);
    expect(router.routerDelegate.state.uri.queryParameters['page'], '1');
  });

  testWidgets('清空收藏夹后显示夹内空状态', (tester) async {
    await setUpFavoritesScreen(
      tester,
      seed: (db) {
        seedCollection(db, id: 'col-empty-page', name: '空夹列表');
      },
      initialLocation: '/favorites/collections/col-empty-page',
    );

    expect(find.textContaining('暂无收藏'), findsOneWidget);
    // 空夹没有可交互的分页栏内容（总数文案不渲染）。
    expect(find.textContaining('共 '), findsNothing);
  });

  testWidgets('翻页查询失败保留旧内容并提供重试', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    seedFavoriteItems(
      db,
      collectionId: '__uncategorized_favorites__',
      count: 25,
    );
    final flaky = _FlakyFavoritesRepository(SqliteFavoritesRepository(db));
    final preferences = await createEmptyPreferences(db);

    Future<void> pumpAt(String location) {
      return repumpFavoritesScreen(
        tester,
        preferences: preferences,
        database: db,
        initialLocation: location,
        extraOverrides: [
          // 故障只注入收藏分页仓库；收藏夹仓库保持真实实现。
          favoritesRepositoryProvider.overrideWithValue(flaky),
          collectionsRepositoryProvider.overrideWithValue(
            SqliteCollectionsRepository(db),
          ),
        ],
        // 排除生产绑定，避免与上述覆盖重复 override。
        bindFavoritesRepositories: false,
      );
    }

    await pumpAt(
      '/favorites/collections/__uncategorized_favorites__?pageSize=10',
    );
    // 列表虚拟化只渲染可视区，断言页首条目锁定第 1 页窗口。
    expect(find.text('问题025'), findsOneWidget);
    expect(find.text('问题016'), findsOneWidget);
    expect(find.textContaining('共 25 条 · 1/3 页'), findsOneWidget);

    // 注入失败后翻到第 2 页：保留旧页内容并出现内联错误与重试入口。
    flaky.failLoadPage = true;
    await tester.tap(
      find.descendant(
        of: find.byType(AppPaginationBar),
        matching: find.text('2'),
      ),
    );
    await tester.pump();

    expect(find.text('加载收藏失败'), findsOneWidget);
    expect(find.text('问题025'), findsOneWidget);

    // 恢复存储后重试成功进入目标页。
    flaky.failLoadPage = false;
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await settleRouteTransition(tester);

    expect(find.text('加载收藏失败'), findsNothing);
    expect(find.text('问题015'), findsOneWidget);
    expect(find.textContaining('共 25 条 · 2/3 页'), findsOneWidget);
  });

  testWidgets('窄屏行布局纵向堆叠且无溢出', (tester) async {
    await _openSystemCollection(
      tester,
      itemCount: 5,
      viewportSize: const Size(360, 800),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('问题005'), findsOneWidget);
    expect(find.textContaining('回复005'), findsOneWidget);
  });
}
