import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';

Favorite _makeFavorite({
  required String id,
  String? collectionId,
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
  return Favorite(
    id: id,
    collectionId: collectionId,
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
    sourceAssistantMessageId: sourceAssistantMessageId,
    title: title,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
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

  group('SqliteFavoritesRepository - loadAll', () {
    test('save 后 loadAll 返回完整的收藏记录，可选字段为 null 时也正确', () {
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

      final result = repository.loadAll();
      expect(result, hasLength(2));
      final full = result.firstWhere((f) => f.id == 'fav-1');
      expect(full.userMessageContent, '用户消息');
      expect(full.assistantContent, '模型回复');
      expect(full.assistantReasoningContent, '思考过程');
      expect(full.sourceConversationId, 'conv-1');
      expect(full.sourceConversationTitle, '对话标题');
      expect(full.sourceAssistantMessageId, 'msg-42');
      expect(full.title, '持久化标题');
      expect(full.assistantModelDisplayName, 'GPT-4.1');
      final minimal = result.firstWhere((f) => f.id == 'fav-2');
      expect(minimal.sourceAssistantMessageId, isNull);
      expect(minimal.title, isNull);
    });

    test('loadAll 按 created_at 降序排列', () {
      repository.save(_makeFavorite(id: 'fav-1', createdAt: DateTime(2026, 1)));
      repository.save(_makeFavorite(id: 'fav-3', createdAt: DateTime(2026, 3)));
      repository.save(_makeFavorite(id: 'fav-2', createdAt: DateTime(2026, 2)));

      final ids = repository.loadAll().map((f) => f.id).toList();
      expect(ids, ['fav-3', 'fav-2', 'fav-1']);
    });

    test('loadAll(collectionId) 投影：null 全部 / 空串未分类 / 具体 ID 分类', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      collectionsRepo.save(
        FavoriteCollection(id: 'col-2', name: 'B', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'fav-1', collectionId: 'col-1'));
      repository.save(_makeFavorite(id: 'fav-2', collectionId: 'col-2'));
      repository.save(_makeFavorite(id: 'fav-3', collectionId: null));

      // 默认与显式 null 都返回全部
      expect(repository.loadAll(), hasLength(3));
      expect(repository.loadAll(collectionId: null), hasLength(3));

      // 空字符串只返回未分类（collection_id IS NULL）
      final unclassified = repository.loadAll(collectionId: '');
      expect(unclassified, hasLength(1));
      expect(unclassified.first.id, 'fav-3');

      // 具体 collectionId 只返回该收藏夹的记录
      final classified = repository.loadAll(collectionId: 'col-1');
      expect(classified, hasLength(1));
      expect(classified.first.id, 'fav-1');
    });
  });

  group('SqliteFavoritesRepository - save & delete', () {
    test('save 重复 id 执行 REPLACE（更新内容）', () {
      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '旧回答'));
      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '新回答'));

      final result = repository.loadAll();
      expect(result, hasLength(1));
      expect(result.first.assistantContent, '新回答');
    });

    test('delete 后记录不再出现', () {
      repository.save(_makeFavorite(id: 'fav-1'));
      repository.delete('fav-1');

      expect(repository.loadAll(), isEmpty);
    });
  });

  group('SqliteFavoritesRepository - moveToCollection', () {
    test('moveToCollection 生命周期：移入收藏夹后移回未分类', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      collectionsRepo.save(
        FavoriteCollection(id: 'col-2', name: 'B', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'fav-1', collectionId: 'col-1'));

      repository.moveToCollection('fav-1', 'col-2');
      expect(repository.loadAll().single.collectionId, 'col-2');

      repository.moveToCollection('fav-1', null);
      expect(repository.loadAll().single.collectionId, isNull);
    });
  });

  group('SqliteFavoritesRepository - existsByAssistantContent', () {
    test('existsByAssistantContent 覆盖未收藏、已收藏与删除后', () {
      expect(repository.existsByAssistantContent('某段精彩回答'), isFalse);

      repository.save(_makeFavorite(id: 'fav-1', assistantContent: '某段精彩回答'));
      expect(repository.existsByAssistantContent('某段精彩回答'), isTrue);

      repository.delete('fav-1');
      expect(repository.existsByAssistantContent('某段精彩回答'), isFalse);
    });
  });

  group('SqliteFavoritesRepository - updateTitle', () {
    test('updateTitle 生命周期：设置自定义标题后清除', () {
      repository.save(_makeFavorite(id: 'fav-1'));

      repository.updateTitle('fav-1', '我的标题');
      expect(repository.loadAll().single.title, '我的标题');

      repository.updateTitle('fav-1', null);
      expect(repository.loadAll().single.title, isNull);
    });
  });

  group('SqliteFavoritesRepository - loadById', () {
    test('两条记录时按 ID 精确读取完整字段，缺失 ID 返回 null', () {
      // favorites.collection_id 有外键约束，需先存在对应收藏夹。
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(
        _makeFavorite(
          id: 'fav-load-1',
          collectionId: 'col-1',
          assistantContent: '助手回复',
          userMessageContent: '用户消息',
          assistantReasoningContent: '推理过程',
          assistantModelDisplayName: 'DeepSeek V4 Flash',
          sourceConversationId: 'conv-1',
          sourceConversationTitle: '原始对话',
          sourceAssistantMessageId: 'msg-1',
          title: '自定义标题',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      repository.save(
        _makeFavorite(id: 'fav-load-2', createdAt: DateTime(2026, 1, 2)),
      );

      final loaded = repository.loadById('fav-load-1');
      expect(loaded, isNotNull);
      expect(loaded!.id, 'fav-load-1');
      expect(loaded.collectionId, 'col-1');
      expect(loaded.userMessageContent, '用户消息');
      expect(loaded.assistantContent, '助手回复');
      expect(loaded.assistantReasoningContent, '推理过程');
      expect(loaded.assistantModelDisplayName, 'DeepSeek V4 Flash');
      expect(loaded.sourceConversationId, 'conv-1');
      expect(loaded.sourceConversationTitle, '原始对话');
      expect(loaded.sourceAssistantMessageId, 'msg-1');
      expect(loaded.title, '自定义标题');
      // createdAt 不同仍按 ID 而非排序命中目标记录
      expect(loaded.createdAt, DateTime(2026, 1, 1));

      expect(repository.loadById('missing-id'), isNull);
    });
  });
}
