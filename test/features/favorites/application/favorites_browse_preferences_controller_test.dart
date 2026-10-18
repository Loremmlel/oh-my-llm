import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_browse_preferences_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection_delete_request.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_collection_summary.dart';

/// 只实现存在性查询的假收藏夹仓库。
class _StubCollectionsRepository implements CollectionsRepository {
  _StubCollectionsRepository(this.collections);

  final List<FavoriteCollection> collections;

  @override
  List<FavoriteCollection> loadAll() => collections;

  @override
  List<FavoriteCollectionSummary> loadSummaries() => throw UnimplementedError();

  @override
  void save(FavoriteCollection collection) => throw UnimplementedError();

  @override
  int delete(
    String collectionId, {
    required CollectionDeleteRequest disposition,
  }) => throw UnimplementedError();
}

void main() {
  ProviderContainer createContainer(
    SharedPreferences preferences, {
    List<FavoriteCollection> collections = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        collectionsRepositoryProvider.overrideWithValue(
          _StubCollectionsRepository(collections),
        ),
      ],
    );
    return container;
  }

  group('FavoritesLastCollectionController', () {
    test('合法持久化值在收藏夹仍存在时复活', () async {
      SharedPreferences.setMockInitialValues({
        favoritesLastCollectionStorageKey: 'col-keep',
      });
      final container = createContainer(
        await SharedPreferences.getInstance(),
        collections: [
          FavoriteCollection(
            id: 'col-keep',
            name: 'K',
            createdAt: DateTime(2026),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(favoritesLastCollectionProvider), 'col-keep');
    });

    test('持久化值指向已删除收藏夹时回退系统收藏夹', () async {
      SharedPreferences.setMockInitialValues({
        favoritesLastCollectionStorageKey: 'col-deleted',
      });
      final container = createContainer(await SharedPreferences.getInstance());
      addTearDown(container.dispose);

      expect(
        container.read(favoritesLastCollectionProvider),
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
    });
  });
}
