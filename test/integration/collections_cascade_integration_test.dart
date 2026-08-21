/// 收藏夹删除级联集成测试。
///
/// 验证 v14 起删除普通收藏夹时，关联收藏在同一事务内移入系统"未分类"
/// 收藏夹：收藏数据保留且归属非空，系统收藏夹始终存在。
library;

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

import '../helpers/integration_test_helpers.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late ProviderContainer container;

  setUp(() async {
    preferences = await createSeededPreferences();
    database = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        favoritesRepositoryProvider.overrideWithValue(
          SqliteFavoritesRepository(database),
        ),
        collectionsRepositoryProvider.overrideWithValue(
          SqliteCollectionsRepository(database),
        ),
        favoritesClockProvider.overrideWithValue(() => DateTime(2026, 8, 21)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
  });

  // ── 删除收藏夹 -> 关联收藏移入系统未分类 ────────────────────────────────────

  test('删除收藏夹后关联收藏自动移入系统未分类', () {
    final library = container.read(favoritesLibraryProvider.notifier);
    final favId = library.add(
      userMessageContent: '用户消息',
      assistantContent: '助手回复',
      collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    final collectionId = library.createCollection('测试收藏夹');

    library.moveMany({favId}, targetCollectionId: collectionId);

    expect(
      container.read(favoriteByIdProvider(favId))!.collectionId,
      collectionId,
    );

    library.deleteCollection(collectionId);

    final collections = container.read(collectionsProvider);
    expect(collections.map((c) => c.id), [
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    ]);

    // mutation 后 by-ID 投影随 revision 重读。
    final favorite = container.read(favoriteByIdProvider(favId))!;
    expect(favorite.id, favId);
    expect(
      favorite.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
  });

  // ── 多个收藏夹中仅删一个 -> 其他收藏夹的收藏不受影响 ──────────────────────────

  test('删除一个收藏夹不影响其他收藏夹中的收藏', () {
    final library = container.read(favoritesLibraryProvider.notifier);
    final fav1Id = library.add(
      userMessageContent: '消息1',
      assistantContent: '回复1',
      collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    final fav2Id = library.add(
      userMessageContent: '消息2',
      assistantContent: '回复2',
      collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
    );

    final colA = library.createCollection('收藏夹A');
    final colB = library.createCollection('收藏夹B');

    library.moveMany({fav1Id}, targetCollectionId: colA);
    library.moveMany({fav2Id}, targetCollectionId: colB);

    library.deleteCollection(colA);

    final fav1 = container.read(favoriteByIdProvider(fav1Id))!;
    final fav2 = container.read(favoriteByIdProvider(fav2Id))!;
    expect(
      fav1.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    expect(fav2.collectionId, colB);
  });
}
