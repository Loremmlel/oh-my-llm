import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection_delete_request.dart';
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
          disposition: const DeleteItemsOnCollectionDelete(),
        ),
        throwsArgumentError,
      );
      expect(repository.loadAll(), hasLength(1));
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

    test('loadAll 与 loadSummaries 同序：系统夹置顶、普通夹按名称稳定排序', () {
      for (final (id, name, createdAt) in [
        ('col-beta', 'Beta', DateTime(2026, 3, 1)),
        ('col-alpha-2', 'Alpha', DateTime(2026, 5, 1)),
        ('col-alpha-1', 'Alpha', DateTime(2026, 1, 1)),
      ]) {
        repository.save(
          FavoriteCollection(id: id, name: name, createdAt: createdAt),
        );
      }

      // 选择器与卡片投影共用同一排序：系统夹恒置顶，普通夹按名称、id
      // tie-break，与创建时间无关。
      final expectedIds = [
        AppReservedEntities.uncategorizedFavoriteCollectionId,
        'col-alpha-1',
        'col-alpha-2',
        'col-beta',
      ];
      expect(repository.loadAll().map((c) => c.id), expectedIds);
      expect(
        repository.loadSummaries().map((s) => s.collection.id),
        expectedIds,
      );
    });
  });

  group('SqliteCollectionsRepository - loadSummaries', () {
    test('空系统夹仍返回且置顶，最近收录时间回退夹创建时间', () {
      final summaries = repository.loadSummaries();

      expect(summaries, hasLength(1));
      final system = summaries.single;
      expect(
        system.collection.id,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(system.itemCount, 0);
      expect(system.recentAssignedAt, system.collection.createdAt);
    });

    test('count 与最近收录时间正确反映归属状态', () {
      repository.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-old',
          collectionId: 'col-1',
          collectionAssignedAt: DateTime(2026, 2, 1),
          userMessageContent: '问题一',
          assistantContent: '回答一',
          createdAt: DateTime(2026, 2, 1),
        ),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-new',
          collectionId: 'col-1',
          collectionAssignedAt: DateTime(2026, 5, 1),
          userMessageContent: '问题二',
          assistantContent: '回答二',
          createdAt: DateTime(2026, 5, 1),
        ),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-sys',
          collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
          collectionAssignedAt: DateTime(2026, 3, 1),
          userMessageContent: '系统夹问题',
          assistantContent: '系统夹回答',
          createdAt: DateTime(2026, 3, 1),
        ),
      );

      final byId = {
        for (final s in repository.loadSummaries()) s.collection.id: s,
      };
      final col1 = byId['col-1']!;
      expect(col1.itemCount, 2);
      expect(col1.recentAssignedAt, DateTime(2026, 5, 1));

      final system =
          byId[AppReservedEntities.uncategorizedFavoriteCollectionId]!;
      expect(system.itemCount, 1);
      expect(system.recentAssignedAt, DateTime(2026, 3, 1));
    });

    test('移动旧收藏进入收藏夹后 recentAssignedAt 更新为移动时刻', () {
      repository.save(
        FavoriteCollection(
          id: 'col-late',
          name: '晚建夹',
          createdAt: DateTime(2026, 6, 1),
        ),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-ancient',
          collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
          collectionAssignedAt: DateTime(2026, 1, 1),
          userMessageContent: '老问题',
          assistantContent: '老回答',
          createdAt: DateTime(2025, 12, 1),
        ),
      );

      favoritesRepository.moveMany(
        {'fav-ancient'},
        targetCollectionId: 'col-late',
        assignedAt: DateTime(2026, 8, 15),
      );

      final summary = repository.loadSummaries().firstWhere(
        (s) => s.collection.id == 'col-late',
      );
      expect(summary.itemCount, 1);
      expect(summary.recentAssignedAt, DateTime(2026, 8, 15));
    });
  });

  group('SqliteCollectionsRepository - typed delete', () {
    void seedCollectionWithFavorite(String collectionId) {
      repository.save(
        FavoriteCollection(
          id: collectionId,
          name: '待删夹 $collectionId',
          createdAt: DateTime(2026),
        ),
      );
      favoritesRepository.save(
        Favorite(
          id: 'fav-of-$collectionId',
          collectionId: collectionId,
          collectionAssignedAt: DateTime(2026, 1, 1),
          userMessageContent: '问题',
          assistantContent: '回答',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }

    test('默认移动处置：收藏转入系统未分类且返回受影响数量', () {
      seedCollectionWithFavorite('col-del-move');

      final affected = repository.delete(
        'col-del-move',
        disposition: CollectionDeleteRequest.moveItemsTo(
          targetCollectionId:
              AppReservedEntities.uncategorizedFavoriteCollectionId,
          assignedAt: DateTime(2026, 8, 20),
        ),
      );

      expect(affected, 1);
      expect(repository.loadSummaries(), hasLength(1));

      final favorite = favoritesRepository.loadById('fav-of-col-del-move')!;
      expect(
        favorite.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(favorite.collectionAssignedAt, DateTime(2026, 8, 20));
    });

    test('指定目标移动处置：收藏转入指定普通收藏夹', () {
      seedCollectionWithFavorite('col-from');
      repository.save(
        FavoriteCollection(
          id: 'col-target',
          name: '目标夹',
          createdAt: DateTime(2026),
        ),
      );

      final affected = repository.delete(
        'col-from',
        disposition: CollectionDeleteRequest.moveItemsTo(
          targetCollectionId: 'col-target',
          assignedAt: DateTime(2026, 8, 21),
        ),
      );

      expect(affected, 1);
      expect(
        favoritesRepository.loadById('fav-of-col-from')!.collectionId,
        'col-target',
      );
    });

    test('危险删除处置：夹内收藏一并删除', () {
      seedCollectionWithFavorite('col-danger');

      final affected = repository.delete(
        'col-danger',
        disposition: const DeleteItemsOnCollectionDelete(),
      );

      expect(affected, 1);
      expect(favoritesRepository.loadById('fav-of-col-danger'), isNull);
      expect(repository.loadSummaries(), hasLength(1));
    });

    test('事务任一步失败时全部回滚', () {
      seedCollectionWithFavorite('col-rollback');

      // 在 favorites 表上挂 BEFORE DELETE 触发器迫使删除处置在事务中途失败。
      database.connection.execute('''
        CREATE TRIGGER abort_favorite_delete
        BEFORE DELETE ON favorites
        BEGIN
          SELECT RAISE(ABORT, '测试注入的删除失败');
        END;
      ''');

      expect(
        () => repository.delete(
          'col-rollback',
          disposition: const DeleteItemsOnCollectionDelete(),
        ),
        throwsA(isA<Exception>()),
      );

      // 收藏与收藏夹都必须原样保留。
      expect(favoritesRepository.loadById('fav-of-col-rollback'), isNotNull);
      expect(
        repository.loadSummaries().where((s) => !s.collection.isSystem),
        hasLength(1),
      );
    });

    test('移动处置的目标不存在或等于被删夹本身时显式拒绝', () {
      seedCollectionWithFavorite('col-self');

      expect(
        () => repository.delete(
          'col-self',
          disposition: CollectionDeleteRequest.moveItemsTo(
            targetCollectionId: 'missing-target',
            assignedAt: DateTime(2026, 8, 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.delete(
          'col-self',
          disposition: CollectionDeleteRequest.moveItemsTo(
            targetCollectionId: 'col-self',
            assignedAt: DateTime(2026, 8, 1),
          ),
        ),
        throwsArgumentError,
      );
      // 拒绝后数据原样保留。
      expect(favoritesRepository.loadById('fav-of-col-self'), isNotNull);
    });
  });
}
