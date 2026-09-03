import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite_page.dart';

Favorite _makeFavorite({
  required String id,
  String? collectionId,
  DateTime? collectionAssignedAt,
  String assistantContent = '助手回复',
  String userMessageContent = '用户消息',
  String assistantReasoningContent = '',
  String assistantModelDisplayName = '匿名模型',
  String? sourceConversationId,
  String? sourceConversationTitle,
  String? sourceAssistantMessageId,
  String? title,
  DateTime? createdAt,
}) {
  final resolvedCreatedAt = createdAt ?? DateTime(2026, 1, 1);
  return Favorite(
    id: id,
    // 未显式指定的收藏归入系统"未分类"收藏夹。
    collectionId:
        collectionId ?? AppReservedEntities.uncategorizedFavoriteCollectionId,
    collectionAssignedAt: collectionAssignedAt ?? resolvedCreatedAt,
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
    sourceAssistantMessageId: sourceAssistantMessageId,
    title: title,
    createdAt: resolvedCreatedAt,
  );
}

void main() {
  late AppDatabase database;
  late SqliteFavoritesRepository repository;
  late SqliteCollectionsRepository collectionsRepo;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteFavoritesRepository(database);
    collectionsRepo = SqliteCollectionsRepository(database);
  });

  tearDown(() {
    database.close();
  });

  /// 读取系统未分类收藏夹整页，作为全量语义的验证通道。
  FavoritePage loadUncategorizedPage() => repository.loadPage(
    collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
    limit: 20,
    offset: 0,
  );

  group('SqliteFavoritesRepository - save & delete', () {
    test('save 后 loadById 返回完整的收藏记录，可选字段为 null 时也正确', () {
      repository.save(
        _makeFavorite(
          id: 'fav-1',
          userMessageContent: '用户消息',
          assistantContent: '模型回复',
          assistantReasoningContent: '思考过程',
          sourceConversationId: 'conv-1',
          sourceConversationTitle: '对话标题',
          sourceAssistantMessageId: 'msg-42',
          title: '持久化标题',
          assistantModelDisplayName: 'GPT-4.1',
        ),
      );
      repository.save(_makeFavorite(id: 'fav-2'));

      final full = repository.loadById('fav-1')!;
      expect(full.userMessageContent, '用户消息');
      expect(full.assistantContent, '模型回复');
      expect(full.assistantReasoningContent, '思考过程');
      expect(full.sourceConversationId, 'conv-1');
      expect(full.sourceConversationTitle, '对话标题');
      expect(full.sourceAssistantMessageId, 'msg-42');
      expect(full.title, '持久化标题');
      expect(full.assistantModelDisplayName, 'GPT-4.1');
      expect(
        full.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(full.collectionAssignedAt, full.createdAt);
      final minimal = repository.loadById('fav-2')!;
      expect(minimal.sourceAssistantMessageId, isNull);
      expect(minimal.title, isNull);
    });

    test('save 重复 id 执行 REPLACE（更新内容）', () {
      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '旧回答'));
      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '新回答'));

      expect(repository.loadById('fav-1')!.assistantContent, '新回答');
      expect(loadUncategorizedPage().totalItems, 1);
    });

    test('save 完整保留归属与归属时间', () {
      // favorites.collection_id 有外键约束，目标收藏夹需先存在。
      collectionsRepo.save(
        FavoriteCollection(
          id: 'col-keep',
          name: 'K',
          createdAt: DateTime(2026),
        ),
      );
      repository.save(
        _makeFavorite(
          id: 'fav-assign',
          collectionId: 'col-keep',
          collectionAssignedAt: DateTime(2026, 5, 1, 12, 30),
          createdAt: DateTime(2026, 4, 1),
        ),
      );

      final loaded = repository.loadById('fav-assign')!;
      expect(loaded.collectionId, 'col-keep');
      expect(loaded.collectionAssignedAt, DateTime(2026, 5, 1, 12, 30));
      expect(loaded.createdAt, DateTime(2026, 4, 1));
    });
  });

  group('SqliteFavoritesRepository - findByAssistantContent', () {
    test('findByAssistantContent 覆盖未收藏、已收藏与删除后', () {
      expect(repository.findByAssistantContent('某段精彩回答'), isNull);

      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '某段精彩回答'));
      expect(repository.findByAssistantContent('某段精彩回答'), isNotNull);

      repository.deleteMany({'fav-1'});
      expect(repository.findByAssistantContent('某段精彩回答'), isNull);
    });
  });

  group('SqliteFavoritesRepository - updateTitle', () {
    test('updateTitle 生命周期：设置自定义标题后清除', () {
      repository.save(_makeFavorite(id: 'fav-1'));

      repository.updateTitle('fav-1', '我的标题');
      expect(repository.loadById('fav-1')!.title, '我的标题');

      repository.updateTitle('fav-1', null);
      expect(repository.loadById('fav-1')!.title, isNull);
    });
  });

  group('SqliteFavoritesRepository - loadPage', () {
    /// 写入 [count] 条系统夹收藏，createdAt 逐条递增。
    void seedSystemFavorites(int count, {String prefix = 'fav'}) {
      for (var i = 1; i <= count; i++) {
        repository.save(
          _makeFavorite(
            id: '$prefix-$i',
            createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }
    }

    test('空收藏夹返回零总数与空页', () {
      final page = repository.loadPage(
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
        limit: 20,
        offset: 0,
      );

      expect(page.items, isEmpty);
      expect(page.totalItems, 0);
    });

    test('21 条按容量 20 分页：第 1 页取最新 20 条且总数正确', () {
      seedSystemFavorites(21);

      final page = repository.loadPage(
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
        limit: 20,
        offset: 0,
      );

      expect(page.items, hasLength(20));
      // created_at DESC：最新条目在前。
      expect(page.items.first.id, 'fav-21');
      expect(page.items.last.id, 'fav-2');
      expect(page.totalItems, 21);
    });

    test('相同 createdAt 时按 id DESC 稳定 tie-break', () {
      for (final id in ['fav-a', 'fav-b', 'fav-c']) {
        repository.save(_makeFavorite(id: id, createdAt: DateTime(2026)));
      }

      final page = repository.loadPage(
        collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
        limit: 20,
        offset: 0,
      );

      expect(page.items.map((f) => f.id), ['fav-c', 'fav-b', 'fav-a']);
    });

    test('只返回指定收藏夹的条目', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'sys-1'));
      repository.save(_makeFavorite(id: 'col-1-fav', collectionId: 'col-1'));

      final page = repository.loadPage(
        collectionId: 'col-1',
        limit: 20,
        offset: 0,
      );

      expect(page.items.map((f) => f.id), ['col-1-fav']);
      expect(page.totalItems, 1);
    });

    test('非法 limit/offset/空 collectionId 显式拒绝', () {
      for (final (limit, offset) in [(0, 0), (-1, 0), (20, -1)]) {
        expect(
          () => repository.loadPage(
            collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
            limit: limit,
            offset: offset,
          ),
          throwsArgumentError,
          reason: 'limit=$limit offset=$offset',
        );
      }
      expect(
        () => repository.loadPage(collectionId: '', limit: 20, offset: 0),
        throwsArgumentError,
      );
    });
  });

  group('SqliteFavoritesRepository - 定向收藏身份查询', () {
    test('loadFavoritedAssistantContents 只返回请求集合中已收藏的内容', () {
      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '已收藏甲'));
      repository.save(_makeFavorite(id: 'fav-2', assistantContent: '已收藏乙'));

      final favorited = repository.loadFavoritedAssistantContents([
        '已收藏甲',
        '未收藏丙',
        '已收藏乙',
      ]);
      expect(favorited, {'已收藏甲', '已收藏乙'});

      // 空集合不生成 IN () 且直接返回空结果。
      expect(repository.loadFavoritedAssistantContents(const []), isEmpty);
    });
  });

  group('SqliteFavoritesRepository - 批量 mutation', () {
    test('deleteMany 批量删除并返回受影响数量，空集合 no-op', () {
      repository.save(_makeFavorite(id: 'fav-1'));
      repository.save(_makeFavorite(id: 'fav-2'));
      repository.save(_makeFavorite(id: 'fav-3'));

      expect(repository.deleteMany({'fav-1', 'fav-3'}), 2);
      expect(loadUncategorizedPage().items.map((f) => f.id), ['fav-2']);

      expect(repository.deleteMany(const {}), 0);
      expect(loadUncategorizedPage().totalItems, 1);
    });

    test('moveMany 批量移动并统一更新归属时间，空集合 no-op', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(
        _makeFavorite(
          id: 'fav-1',
          createdAt: DateTime(2026, 1, 1),
          collectionAssignedAt: DateTime(2026, 1, 1),
        ),
      );
      repository.save(
        _makeFavorite(
          id: 'fav-2',
          createdAt: DateTime(2026, 1, 2),
          collectionAssignedAt: DateTime(2026, 1, 2),
        ),
      );

      final movedCount = repository.moveMany(
        {'fav-1', 'fav-2'},
        targetCollectionId: 'col-1',
        assignedAt: DateTime(2026, 8, 1),
      );
      expect(movedCount, 2);

      for (final id in ['fav-1', 'fav-2']) {
        final favorite = repository.loadById(id)!;
        expect(favorite.collectionId, 'col-1');
        expect(favorite.collectionAssignedAt, DateTime(2026, 8, 1));
      }

      expect(
        repository.moveMany(
          const {},
          targetCollectionId: 'col-1',
          assignedAt: DateTime(2026, 8, 2),
        ),
        0,
      );
    });

    test('moveMany 目标收藏夹不存在时被外键拒绝', () {
      repository.save(_makeFavorite(id: 'fav-1'));

      expect(
        () => repository.moveMany(
          {'fav-1'},
          targetCollectionId: 'missing-col',
          assignedAt: DateTime(2026, 8, 1),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
