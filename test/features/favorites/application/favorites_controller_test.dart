import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_clock_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';

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

  group('favoriteByIdProvider', () {
    test('rename/move/remove 后 by-ID 状态随 revision 同步更新', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      final colX = library.createCollection('X');
      final id = library.add(
        userMessageContent: '问题',
        assistantContent: '回复',
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      );

      library.rename(id, '新标题');
      expect(container.read(favoriteByIdProvider(id))!.title, '新标题');

      library.moveMany({id}, targetCollectionId: colX);
      expect(container.read(favoriteByIdProvider(id))!.collectionId, colX);

      library.remove(id);
      expect(container.read(favoriteByIdProvider(id)), isNull);
    });
  });

  group('collectionsProvider 可见列表', () {
    test('系统夹恒可见且同名普通行被过滤', () {
      final library = container.read(favoritesLibraryProvider.notifier);
      // 直接经 repository 写入历史残留的同名普通行。
      container
          .read(collectionsRepositoryProvider)
          .save(
            FavoriteCollection(
              id: 'col-legacy-name',
              name: '未分类',
              createdAt: DateTime(2026),
            ),
          );
      final normalId = library.createCollection('工作笔记');

      final visible = container.read(collectionsProvider);
      expect(visible.map((c) => c.id), [
        AppReservedEntities.uncategorizedFavoriteCollectionId,
        normalId,
      ]);
    });
  });
}
