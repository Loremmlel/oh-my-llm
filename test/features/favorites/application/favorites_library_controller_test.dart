import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_browse_preferences_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_clock_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        favoritesRepositoryProvider.overrideWith(
          (ref) => SqliteFavoritesRepository(database),
        ),
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

  group('FavoritesLibraryController revision', () {
    int revision() => container.read(favoritesLibraryProvider);

    test('初始 revision 为 0，成功的 add/rename/create/move/remove 各递增一次', () {
      expect(revision(), 0);
      final library = container.read(favoritesLibraryProvider.notifier);

      final id = library.add(
        userMessageContent: '问题',
        assistantContent: '回答',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(revision(), 1);

      library.rename(id, '标题');
      expect(revision(), 2);

      final colId = library.createCollection('新夹');
      expect(revision(), 3);

      library.moveMany({id}, targetCollectionId: colId);
      expect(revision(), 4);

      library.remove(id);
      expect(revision(), 5);
    });

    test('批量删除与删除收藏夹同样逐次递增 revision', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final idA = library.add(
        userMessageContent: '问题甲',
        assistantContent: '回答甲',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      final idB = library.add(
        userMessageContent: '问题乙',
        assistantContent: '回答乙',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );

      library.deleteMany({idA, idB});
      expect(revision(), 3);

      final colId = library.createCollection('待删夹');
      library.deleteCollection(colId);
      expect(revision(), 5);
    });

    test('操作失败时不递增 revision', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final id = library.add(
        userMessageContent: '问题',
        assistantContent: '回答',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      final baseline = revision();

      // 目标收藏夹不存在：外键拒绝，mutation 抛出且 revision 不变。
      expect(
        () => library.moveMany({id}, targetCollectionId: 'missing-col'),
        throwsA(isA<Exception>()),
      );
      expect(revision(), baseline);
    });

    test('query readers 跟随 revision 失效：by-ID 与 summaries 同步更新', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final id = library.add(
        userMessageContent: '问题',
        assistantContent: '回答',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(container.read(favoriteByIdProvider(id)), isNotNull);

      library.rename(id, '新标题');
      expect(container.read(favoriteByIdProvider(id))!.title, '新标题');

      final colId = library.createCollection('迁移夹');
      library.moveMany({id}, targetCollectionId: colId);
      expect(container.read(favoriteByIdProvider(id))!.collectionId, colId);

      // summaries 反映移动后的归属分布。
      final summaries = {
        for (final s in container.read(collectionsSummariesProvider))
          s.collection.id: s,
      };
      expect(summaries[colId]!.itemCount, 1);
      expect(
        summaries[AppReservedEntities.uncategorizedFavoriteCollectionId]!
            .itemCount,
        0,
      );
    });

    test('成功归类更新最近收藏夹，删除该夹后回退系统夹且不留孤儿 ID', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final colId = library.createCollection('常用夹');
      // 归类动作本身写入最近收藏夹偏好。
      library.add(
        userMessageContent: '问题',
        assistantContent: '回答',
        collectionId: colId,
      );
      expect(container.read(favoritesLastCollectionProvider), colId);

      library.deleteCollection(colId);

      expect(
        container.read(favoritesLastCollectionProvider),
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      // summaries 中只剩系统夹。
      expect(
        container
            .read(collectionsSummariesProvider)
            .map((s) => s.collection.id),
        [AppReservedEntities.uncategorizedFavoriteCollectionId],
      );
    });
  });
}
