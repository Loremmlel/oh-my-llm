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
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
  });

  // ── 删除收藏夹 -> 关联收藏移入系统未分类 ────────────────────────────────────

  test('删除收藏夹后关联收藏自动移入系统未分类', () async {
    final favId = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '用户消息', assistantContent: '助手回复');
    final collectionId = container
        .read(collectionsProvider.notifier)
        .create('测试收藏夹');

    container.read(favoritesProvider.notifier).moveTo(favId, collectionId);

    var favorites = container.read(favoritesProvider);
    expect(favorites.first.collectionId, collectionId);

    container.read(collectionsProvider.notifier).delete(collectionId);

    final collections = container.read(collectionsProvider);
    expect(collections.map((c) => c.id), [
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    ]);

    // 收藏夹删除后 favoritesProvider 状态尚未刷新，切换过滤条件触发重建
    container.read(favoritesFilterProvider.notifier).setFilter('');
    favorites = container.read(favoritesProvider);
    expect(favorites, hasLength(1));
    expect(favorites.first.id, favId);
    expect(
      favorites.first.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
  });

  // ── 多个收藏夹中仅删一个 -> 其他收藏夹的收藏不受影响 ──────────────────────────

  test('删除一个收藏夹不影响其他收藏夹中的收藏', () async {
    final fav1Id = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '消息1', assistantContent: '回复1');
    final fav2Id = container
        .read(favoritesProvider.notifier)
        .add(userMessageContent: '消息2', assistantContent: '回复2');

    final colA = container.read(collectionsProvider.notifier).create('收藏夹A');
    final colB = container.read(collectionsProvider.notifier).create('收藏夹B');

    container.read(favoritesProvider.notifier).moveTo(fav1Id, colA);
    container.read(favoritesProvider.notifier).moveTo(fav2Id, colB);

    container.read(collectionsProvider.notifier).delete(colA);

    // 收藏夹删除后 favoritesProvider 状态尚未刷新，切换过滤条件触发重建
    container.read(favoritesFilterProvider.notifier).setFilter('');
    container.read(favoritesFilterProvider.notifier).setFilter(null);
    final favorites = container.read(favoritesProvider);
    final fav1 = favorites.firstWhere((f) => f.id == fav1Id);
    final fav2 = favorites.firstWhere((f) => f.id == fav2Id);
    expect(
      fav1.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    expect(fav2.collectionId, colB);
  });
}
