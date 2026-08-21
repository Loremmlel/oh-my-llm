import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_browser_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_clock_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_page.dart';

/// 可切换分页查询失败的收藏仓库装饰器，模拟浏览器刷新时存储不可用。
class _FlakyFavoritesRepository implements FavoritesRepository {
  _FlakyFavoritesRepository(this._inner);

  final FavoritesRepository _inner;
  bool failLoadPage = false;

  @override
  FavoritePage loadPage({
    required String collectionId,
    required int limit,
    required int offset,
  }) {
    if (failLoadPage) {
      throw StateError('模拟分页查询失败');
    }
    return _inner.loadPage(
      collectionId: collectionId,
      limit: limit,
      offset: offset,
    );
  }

  @override
  List<Favorite> loadAll() => _inner.loadAll();

  @override
  Favorite? loadById(String favoriteId) => _inner.loadById(favoriteId);

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
  int deleteMany(Set<String> favoriteIds) => _inner.deleteMany(favoriteIds);

  @override
  int moveMany(
    Set<String> favoriteIds, {
    required String targetCollectionId,
    required DateTime assignedAt,
  }) => _inner.moveMany(
    favoriteIds,
    targetCollectionId: targetCollectionId,
    assignedAt: assignedAt,
  );

  @override
  void updateTitle(String favoriteId, String? title) =>
      _inner.updateTitle(favoriteId, title);
}

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late _FlakyFavoritesRepository flakyRepository;

  /// 写入 [count] 条系统夹收藏，createdAt 逐条递增保证稳定排序。
  void seedSystemFavorites(int count) {
    final repository = container.read(favoritesRepositoryProvider);
    for (var i = 1; i <= count; i++) {
      repository.save(
        Favorite(
          id: 'fav-$i',
          collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
          collectionAssignedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          userMessageContent: '问题$i',
          assistantContent: '回答$i',
          createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }
  }

  setUp(() async {
    database = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    flakyRepository = _FlakyFavoritesRepository(
      SqliteFavoritesRepository(database),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        favoritesRepositoryProvider.overrideWithValue(flakyRepository),
        collectionsRepositoryProvider.overrideWith(
          (ref) => SqliteCollectionsRepository(database),
        ),
        favoritesClockProvider.overrideWithValue(() => DateTime(2026, 8, 21)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    database.close();
  });

  group('FavoriteBrowserController', () {
    test('初始状态为未初始化的系统夹空窗口', () {
      final state = container.read(favoriteBrowserProvider);

      expect(state.isInitialized, isFalse);
      expect(state.items, isEmpty);
      expect(
        state.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(state.errorMessage, isNull);
    });

    test('loadRoute 加载指定收藏夹的当前页窗口', () {
      seedSystemFavorites(21);

      container.read(favoriteBrowserProvider.notifier).loadRoute(page: 1);

      final state = container.read(favoriteBrowserProvider);
      expect(state.isInitialized, isTrue);
      expect(state.items, hasLength(20));
      expect(state.totalItems, 21);
      expect(state.page, 1);
    });

    test('loadRoute 指定容量与页码时加载对应窗口', () {
      seedSystemFavorites(21);

      container
          .read(favoriteBrowserProvider.notifier)
          .loadRoute(page: 2, pageSize: 10);

      final state = container.read(favoriteBrowserProvider);
      // created_at DESC：第 2 页为第 11-20 新的条目。
      expect(state.items.first.userMessageContent, '问题11');
      expect(state.items, hasLength(10));
      expect(state.totalItems, 21);
      expect(state.pageSize, 10);
      expect(state.page, 2);
    });

    test('route 页码越界时按真实总数夹取到最后一页', () {
      seedSystemFavorites(21);

      container
          .read(favoriteBrowserProvider.notifier)
          .loadRoute(page: 99, pageSize: 10);

      final state = container.read(favoriteBrowserProvider);
      expect(state.page, 3);
      expect(state.items, hasLength(1));
      expect(state.items.single.userMessageContent, '问题1');
    });

    test('切换 route 到其他收藏夹时窗口跟随', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final colA = library.createCollection('夹甲');
      container
          .read(favoritesRepositoryProvider)
          .save(
            Favorite(
              id: 'fav-in-a',
              collectionId: colA,
              collectionAssignedAt: DateTime(2026),
              userMessageContent: '夹内问题',
              assistantContent: '夹内回答',
              createdAt: DateTime(2026),
            ),
          );

      container
          .read(favoriteBrowserProvider.notifier)
          .loadRoute(collectionId: colA);

      final state = container.read(favoriteBrowserProvider);
      expect(state.collectionId, colA);
      expect(state.items.map((f) => f.id), ['fav-in-a']);
      expect(state.totalItems, 1);
    });

    test('mutation 后自动刷新并补齐当前页', () {
      seedSystemFavorites(21);
      container.read(favoriteBrowserProvider.notifier).loadRoute();

      // 删除第 1 页的一条后，原第 2 页首项应补入当前页。
      container.read(favoritesLibraryProvider.notifier).deleteMany({'fav-21'});

      final state = container.read(favoriteBrowserProvider);
      expect(state.items, hasLength(20));
      expect(state.totalItems, 20);
      // 补入的是排序紧随其后的条目。
      expect(state.items.map((f) => f.id), contains('fav-1'));
      expect(state.items.map((f) => f.id), isNot(contains('fav-21')));
    });

    test('删除当前浏览的收藏夹后回退系统夹窗口', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final colB = library.createCollection('待删夹');
      container
          .read(favoriteBrowserProvider.notifier)
          .loadRoute(collectionId: colB);
      expect(container.read(favoriteBrowserProvider).collectionId, colB);

      library.deleteCollection(colB);

      final state = container.read(favoriteBrowserProvider);
      expect(
        state.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(state.isInitialized, isTrue);
    });

    test('查询失败时保留旧窗口内容并写入错误信息', () {
      seedSystemFavorites(5);
      container.read(favoriteBrowserProvider.notifier).loadRoute();
      final before = container.read(favoriteBrowserProvider);

      // 刷新查询失败（存储不可用），mutation 本身成功。
      flakyRepository.failLoadPage = true;
      container
          .read(favoritesLibraryProvider.notifier)
          .rename('fav-1', '触发刷新失败');

      final state = container.read(favoriteBrowserProvider);
      expect(state.errorMessage, isNotNull);
      // 旧内容保留。
      expect(state.items.map((f) => f.id), before.items.map((f) => f.id));
    });
  });
}
