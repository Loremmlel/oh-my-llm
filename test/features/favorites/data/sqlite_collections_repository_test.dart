import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

void main() {
  late AppDatabase database;
  late SqliteCollectionsRepository repository;
  late SqliteFavoritesRepository favoritesRepository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteCollectionsRepository(database);
    favoritesRepository = SqliteFavoritesRepository(database);
  });

  tearDown(() {
    database.close();
  });

  group('SqliteCollectionsRepository', () {
    test('全新数据库已播种系统未分类收藏夹且不可删除', () {
      final collections = repository.loadAll();
      expect(
        collections.map((c) => c.id),
        contains(AppReservedEntities.uncategorizedFavoriteCollectionId),
      );

      expect(
        () => repository.delete(
          AppReservedEntities.uncategorizedFavoriteCollectionId,
        ),
        throwsArgumentError,
      );
      expect(repository.loadAll(), hasLength(1));
    });

    test('save/delete 生命周期：保存、按 id 更新、删除普通收藏夹', () {
      final original = FavoriteCollection(
        id: 'col-1',
        name: '旧名称',
        createdAt: DateTime(2026, 1, 1),
      );

      repository.save(original);
      expect(
        repository.loadAll().where((c) => c.id == 'col-1').single,
        original,
      );

      repository.save(original.copyWith(name: '新名称'));
      expect(
        repository.loadAll().firstWhere((c) => c.id == 'col-1').name,
        '新名称',
      );

      repository.delete('col-1');
      expect(repository.loadAll().where((c) => c.id == 'col-1'), isEmpty);
    });

    test('rename 走 UPSERT：收藏夹内的收藏不受影响', () {
      // INSERT OR REPLACE 会先删后插触发 RESTRICT 外键级联，
      // rename 含收藏的收藏夹必须保留全部归属关系。
      repository.save(
        FavoriteCollection(
          id: 'col-full',
          name: '旧名',
          createdAt: DateTime(2026),
        ),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-1',
          collectionId: 'col-full',
          collectionAssignedAt: DateTime(2026, 1, 1),
          userMessageContent: '问题',
          assistantContent: '回答',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      repository.save(
        FavoriteCollection(
          id: 'col-full',
          name: '新名',
          createdAt: DateTime(2026),
        ),
      );

      expect(
        repository.loadAll().firstWhere((c) => c.id == 'col-full').name,
        '新名',
      );
      final favorite = favoritesRepository.loadById('fav-1')!;
      expect(favorite.collectionId, 'col-full');
      expect(favorite.collectionAssignedAt, DateTime(2026, 1, 1));
    });

    test('delete 普通收藏夹时把内部收藏移入系统收藏夹并更新归属时间', () {
      repository.save(
        FavoriteCollection(id: 'col-x', name: 'X', createdAt: DateTime(2026)),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-move',
          collectionId: 'col-x',
          collectionAssignedAt: DateTime(2026, 1, 1),
          userMessageContent: '问题',
          assistantContent: '回答',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      repository.delete('col-x');

      expect(repository.loadAll().map((c) => c.id), [
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      ]);
      final favorite = favoritesRepository.loadById('fav-move')!;
      expect(
        favorite.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(favorite.collectionAssignedAt, isNot(DateTime(2026, 1, 1)));
    });

    test('delete 不存在的收藏夹为 no-op', () {
      repository.save(
        FavoriteCollection(id: 'col-y', name: 'Y', createdAt: DateTime(2026)),
      );

      repository.delete('missing');

      expect(repository.loadAll().where((c) => !c.isSystem).single.id, 'col-y');
    });

    test('loadAll 按 created_at 升序排列', () {
      repository.save(
        FavoriteCollection(
          id: 'col-c',
          name: 'C',
          createdAt: DateTime(2026, 3, 1),
        ),
      );
      repository.save(
        FavoriteCollection(
          id: 'col-a',
          name: 'A',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      repository.save(
        FavoriteCollection(
          id: 'col-b',
          name: 'B',
          createdAt: DateTime(2026, 5, 1),
        ),
      );

      final ids = repository.loadAll().map((c) => c.id).toList();
      // ID 顺序不按字母排列，确保按 created_at 而非 ID 排序；
      // 系统收藏夹播种时间为当前时刻，排在测试固定时间之后。
      expect(ids, [
        'col-a',
        'col-c',
        'col-b',
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      ]);
    });
  });
}
