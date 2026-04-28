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
  String? sourceConversationId,
  String? sourceConversationTitle,
  DateTime? createdAt,
}) {
  return Favorite(
    id: id,
    collectionId: collectionId,
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
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
    test('空表返回空列表', () {
      expect(repository.loadAll(), isEmpty);
    });

    test('save 后 loadAll 返回该收藏记录', () {
      final fav = _makeFavorite(id: 'fav-1', assistantContent: '很棒的回答');
      repository.save(fav);

      final result = repository.loadAll();
      expect(result, hasLength(1));
      expect(result.first.id, 'fav-1');
      expect(result.first.assistantContent, '很棒的回答');
    });

    test('loadAll 按 created_at 降序排列', () {
      repository.save(_makeFavorite(id: 'fav-1', createdAt: DateTime(2026, 1)));
      repository.save(_makeFavorite(id: 'fav-3', createdAt: DateTime(2026, 3)));
      repository.save(_makeFavorite(id: 'fav-2', createdAt: DateTime(2026, 2)));

      final ids = repository.loadAll().map((f) => f.id).toList();
      expect(ids, ['fav-3', 'fav-2', 'fav-1']);
    });

    test('null collectionId → 返回所有收藏', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(
        _makeFavorite(id: 'fav-1', collectionId: 'col-1'),
      );
      repository.save(_makeFavorite(id: 'fav-2', collectionId: null));

      expect(repository.loadAll(), hasLength(2));
      expect(repository.loadAll(collectionId: null), hasLength(2));
    });

    test("空字符串 collectionId → 只返回未分类（collection_id IS NULL）", () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(
        _makeFavorite(id: 'fav-1', collectionId: 'col-1'),
      );
      repository.save(_makeFavorite(id: 'fav-2', collectionId: null));

      final result = repository.loadAll(collectionId: '');
      expect(result, hasLength(1));
      expect(result.first.id, 'fav-2');
    });

    test('具体 collectionId → 只返回该收藏夹的记录', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      collectionsRepo.save(
        FavoriteCollection(id: 'col-2', name: 'B', createdAt: DateTime(2026)),
      );
      repository.save(
        _makeFavorite(id: 'fav-1', collectionId: 'col-1'),
      );
      repository.save(
        _makeFavorite(id: 'fav-2', collectionId: 'col-2'),
      );
      repository.save(_makeFavorite(id: 'fav-3', collectionId: null));

      final result = repository.loadAll(collectionId: 'col-1');
      expect(result, hasLength(1));
      expect(result.first.id, 'fav-1');
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

    test('delete 不存在的 id 不抛异常', () {
      expect(() => repository.delete('non-existent'), returnsNormally);
    });

    test('保存带推理内容的收藏记录后正确还原', () {
      final fav = _makeFavorite(
        id: 'fav-1',
        assistantReasoningContent: '深度思考过程...',
      );
      repository.save(fav);

      final result = repository.loadAll().first;
      expect(result.assistantReasoningContent, '深度思考过程...');
      expect(result.hasReasoning, isTrue);
    });

    test('保存含来源对话信息的收藏后正确还原', () {
      final fav = _makeFavorite(
        id: 'fav-1',
        sourceConversationId: 'conv-123',
        sourceConversationTitle: '关于 Dart 的讨论',
      );
      repository.save(fav);

      final result = repository.loadAll().first;
      expect(result.sourceConversationId, 'conv-123');
      expect(result.sourceConversationTitle, '关于 Dart 的讨论');
    });
  });

  group('SqliteFavoritesRepository - moveToCollection', () {
    test('移动到另一个收藏夹后 collection_id 更新', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      collectionsRepo.save(
        FavoriteCollection(id: 'col-2', name: 'B', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'fav-1', collectionId: 'col-1'));

      repository.moveToCollection('fav-1', 'col-2');

      final result = repository.loadAll().first;
      expect(result.collectionId, 'col-2');
    });

    test('移动到未分类（null）后 collection_id 为 null', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'fav-1', collectionId: 'col-1'));

      repository.moveToCollection('fav-1', null);

      final result = repository.loadAll().first;
      expect(result.collectionId, isNull);
    });
  });

  group('SqliteFavoritesRepository - existsByAssistantContent', () {
    test('未收藏时返回 false', () {
      expect(repository.existsByAssistantContent('不存在的内容'), isFalse);
    });

    test('已收藏时返回 true', () {
      repository.save(
        _makeFavorite(id: 'fav-1', assistantContent: '某段精彩回答'),
      );
      expect(repository.existsByAssistantContent('某段精彩回答'), isTrue);
    });

    test('删除后返回 false', () {
      repository.save(
        _makeFavorite(id: 'fav-1', assistantContent: '某段精彩回答'),
      );
      repository.delete('fav-1');
      expect(repository.existsByAssistantContent('某段精彩回答'), isFalse);
    });
  });

  group('SqliteFavoritesRepository - ON DELETE SET NULL（外键级联）', () {
    test('删除收藏夹后其收藏的 collection_id 自动置 null', () {
      collectionsRepo.save(
        FavoriteCollection(id: 'col-1', name: 'A', createdAt: DateTime(2026)),
      );
      repository.save(_makeFavorite(id: 'fav-1', collectionId: 'col-1'));
      repository.save(_makeFavorite(id: 'fav-2', collectionId: 'col-1'));

      collectionsRepo.delete('col-1');

      final all = repository.loadAll();
      expect(all, hasLength(2));
      expect(all.every((f) => f.collectionId == null), isTrue);
    });
  });
}
