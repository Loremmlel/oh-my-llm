import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/widgets/pagination/app_pagination_state.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_page_window_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_clock_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_page.dart';

/// 可切换分页查询失败的仓库，用于验证错误边界不会泄露原始异常。
class _FlakyFavoritesRepository extends SqliteFavoritesRepository {
  _FlakyFavoritesRepository(super.database);

  bool failLoadPage = false;

  @override
  FavoritePage loadPage({
    required String collectionId,
    required int limit,
    required int offset,
  }) {
    if (failLoadPage) {
      throw StateError('不应展示的存储路径与内部错误');
    }
    return super.loadPage(
      collectionId: collectionId,
      limit: limit,
      offset: offset,
    );
  }
}

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late _FlakyFavoritesRepository flakyRepository;

  const systemCollectionId =
      AppReservedEntities.uncategorizedFavoriteCollectionId;

  void seedSystemFavorites(int count) {
    final repository = container.read(favoritesRepositoryProvider);
    for (var i = 1; i <= count; i++) {
      repository.save(
        Favorite(
          id: 'fav-$i',
          collectionId: systemCollectionId,
          collectionAssignedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          userMessageContent: '问题$i',
          assistantContent: '回答$i',
          createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }
  }

  FavoritePageWindow readWindow(FavoritePageQuery query) {
    final result = container.read(favoritePageWindowProvider(query));
    expect(result.hasError, isFalse);
    return result.asData!.value;
  }

  setUp(() async {
    database = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    flakyRepository = _FlakyFavoritesRepository(database);
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

  group('收藏分页窗口查询', () {
    test('路由参数统一规范化为有效收藏夹与分页窗口', () {
      seedSystemFavorites(21);
      final cases =
          <
            ({
              String name,
              FavoritePageQuery query,
              int page,
              int pageSize,
              int itemCount,
              String firstContent,
            })
          >[
            (
              name: '合法第二页',
              query: (collectionId: systemCollectionId, page: 2, pageSize: 10),
              page: 2,
              pageSize: 10,
              itemCount: 10,
              firstContent: '问题11',
            ),
            (
              name: '负页码与非法容量',
              query: (collectionId: systemCollectionId, page: -3, pageSize: 7),
              page: 1,
              pageSize: appDefaultPageSize,
              itemCount: appDefaultPageSize,
              firstContent: '问题21',
            ),
            (
              name: '越界页',
              query: (collectionId: systemCollectionId, page: 99, pageSize: 10),
              page: 3,
              pageSize: 10,
              itemCount: 1,
              firstContent: '问题1',
            ),
            (
              name: '不存在的收藏夹',
              query: (collectionId: 'missing', page: 2, pageSize: 10),
              page: 1,
              pageSize: 10,
              itemCount: 10,
              firstContent: '问题21',
            ),
          ];

      for (final testCase in cases) {
        final window = readWindow(testCase.query);
        expect(
          window.effectiveCollection.id,
          systemCollectionId,
          reason: testCase.name,
        );
        expect(window.canonicalPage, testCase.page, reason: testCase.name);
        expect(window.pageSize, testCase.pageSize, reason: testCase.name);
        expect(
          window.page.items,
          hasLength(testCase.itemCount),
          reason: testCase.name,
        );
        expect(
          window.page.items.first.userMessageContent,
          testCase.firstContent,
          reason: testCase.name,
        );
      }
    });

    test('成功 mutation 后自动重查并补齐当前页', () {
      seedSystemFavorites(21);
      final query = (collectionId: systemCollectionId, page: 1, pageSize: 20);
      expect(readWindow(query).page.totalItems, 21);

      container.read(favoritesLibraryProvider.notifier).deleteMany({'fav-21'});

      final window = readWindow(query);
      expect(window.page.totalItems, 20);
      expect(window.page.items, hasLength(20));
      expect(
        window.page.items.map((favorite) => favorite.id),
        contains('fav-1'),
      );
      expect(
        window.page.items.map((favorite) => favorite.id),
        isNot(contains('fav-21')),
      );
    });

    test('mutation 清空末页后回退新的最后一页', () {
      seedSystemFavorites(21);
      final query = (collectionId: systemCollectionId, page: 3, pageSize: 10);
      expect(readWindow(query).page.items.single.id, 'fav-1');

      container.read(favoritesLibraryProvider.notifier).deleteMany({'fav-1'});

      final window = readWindow(query);
      expect(window.canonicalPage, 2);
      expect(window.page.totalItems, 20);
      expect(window.page.items, hasLength(10));
    });

    test('删除当前收藏夹后回退系统夹', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final collectionId = library.createCollection('待删除收藏夹');
      final query = (collectionId: collectionId, page: 1, pageSize: 20);
      expect(readWindow(query).effectiveCollection.id, collectionId);

      library.deleteCollection(collectionId);

      final window = readWindow(query);
      expect(window.effectiveCollection.id, systemCollectionId);
      expect(window.canonicalPage, 1);
    });

    test('存储异常只返回固定安全错误', () {
      flakyRepository.failLoadPage = true;

      final result = container.read(
        favoritePageWindowProvider((
          collectionId: systemCollectionId,
          page: 1,
          pageSize: 20,
        )),
      );

      expect(result.hasError, isTrue);
      expect(result.asError!.error, favoriteLoadErrorMessage);
      expect('$result', isNot(contains('不应展示的存储路径与内部错误')));
    });
  });
}
