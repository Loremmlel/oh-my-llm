import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/collection.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        favoritesRepositoryProvider.overrideWith(
          (ref) => SqliteFavoritesRepository(database),
        ),
        collectionsRepositoryProvider.overrideWith(
          (ref) => SqliteCollectionsRepository(database),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    database.close();
  });

  group('FavoritesController', () {
    test('add inserts a favorite with all fields into the list', () {
      container.read(collectionsProvider.notifier).create('测试收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: '用户消息',
            assistantContent: '模型回复',
            sourceConversationId: 'conv-1',
            sourceConversationTitle: '对话标题',
            collectionId: collectionId,
          );

      final fav = container.read(favoritesProvider).first;
      expect(fav.userMessageContent, '用户消息');
      expect(fav.assistantContent, '模型回复');
      expect(fav.sourceConversationId, 'conv-1');
      expect(fav.sourceConversationTitle, '对话标题');
      expect(fav.collectionId, collectionId);
    });

    test('remove deletes the favorite from the list', () {
      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '要删除的消息', assistantContent: '要删除的回复');

      final id = container.read(favoritesProvider).first.id;
      container.read(favoritesProvider.notifier).remove(id);

      expect(container.read(favoritesProvider), isEmpty);
    });

    test('isFavorited returns true when content is already favorited', () {
      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '已收藏的内容');

      expect(
        container.read(favoritesProvider.notifier).isFavorited('已收藏的内容'),
        isTrue,
      );
    });

    test('isFavorited returns false when content is not favorited', () {
      expect(
        container.read(favoritesProvider.notifier).isFavorited('未收藏的内容'),
        isFalse,
      );
    });

    test('remove nonexistent id is silently ignored', () {
      container.read(favoritesProvider.notifier).remove('nonexistent');

      expect(container.read(favoritesProvider), isEmpty);
    });

    test('moveTo updates collectionId of the favorite', () {
      container.read(collectionsProvider.notifier).create('目标收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回答');
      final favId = container.read(favoritesProvider).first.id;

      container.read(favoritesProvider.notifier).moveTo(favId, collectionId);

      final moved = container.read(favoritesProvider).first;
      expect(moved.collectionId, collectionId);
    });

    test('moveTo with null moves favorite to uncategorized', () {
      container.read(collectionsProvider.notifier).create('收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: '问题',
            assistantContent: '回答',
            collectionId: collectionId,
          );
      final favId = container.read(favoritesProvider).first.id;

      container.read(favoritesProvider.notifier).moveTo(favId, null);

      final moved = container.read(favoritesProvider).first;
      expect(moved.collectionId, isNull);
    });

    test('rename updates favorite title', () {
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '用户消息', assistantContent: '回复');

      container.read(favoritesProvider.notifier).rename(id, '新标题');

      final favorites = container.read(favoritesProvider);
      final fav = favorites.firstWhere((f) => f.id == id);
      expect(fav.title, '新标题');
    });

    test('rename with null clears custom title', () {
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '用户消息', assistantContent: '回复');
      container.read(favoritesProvider.notifier).rename(id, '临时标题');
      container.read(favoritesProvider.notifier).rename(id, null);

      final favorites = container.read(favoritesProvider);
      final fav = favorites.firstWhere((f) => f.id == id);
      expect(fav.title, isNull);
    });

    test('add 保存 sourceAssistantMessageId', () {
      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: '问题',
            assistantContent: '回答',
            sourceConversationId: 'conv-1',
            sourceAssistantMessageId: 'msg-42',
          );
      final fav = container.read(favoritesProvider).first;
      expect(fav.sourceAssistantMessageId, 'msg-42');
    });
  });

  group('CollectionsController', () {
    test('create adds a collection and returns its id', () {
      final id = container.read(collectionsProvider.notifier).create('我的笔记');

      expect(id, isNotEmpty);
      expect(container.read(collectionsProvider).length, 1);
      expect(container.read(collectionsProvider).first.name, '我的笔记');
    });

    test('create trims whitespace from name', () {
      container.read(collectionsProvider.notifier).create('  带空格  ');

      expect(container.read(collectionsProvider).first.name, '带空格');
    });

    test('rename updates the collection name', () {
      container.read(collectionsProvider.notifier).create('旧名字');
      final id = container.read(collectionsProvider).first.id;

      container.read(collectionsProvider.notifier).rename(id, '新名字');

      expect(container.read(collectionsProvider).first.name, '新名字');
    });

    test('rename trims whitespace', () {
      container.read(collectionsProvider.notifier).create('原名');
      final id = container.read(collectionsProvider).first.id;

      container.read(collectionsProvider.notifier).rename(id, '  新名  ');

      expect(container.read(collectionsProvider).first.name, '新名');
    });

    test('delete removes the collection', () {
      container.read(collectionsProvider.notifier).create('要删除');
      final id = container.read(collectionsProvider).first.id;

      container.read(collectionsProvider.notifier).delete(id);

      expect(container.read(collectionsProvider), isEmpty);
    });

    test('rename nonexistent id is silently ignored', () {
      container.read(collectionsProvider.notifier).rename('nonexistent', '名字');

      expect(container.read(collectionsProvider), isEmpty);
    });

    test('delete nonexistent id is silently ignored', () {
      container.read(collectionsProvider.notifier).create('保留');
      final id = container.read(collectionsProvider).first.id;

      container.read(collectionsProvider.notifier).delete('nonexistent');

      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).first.id, id);
    });
  });

  group('FavoritesFilterNotifier', () {
    test('初始状态为 null（全部）', () {
      expect(container.read(favoritesFilterProvider), isNull);
    });

    test('setFilter 更新过滤条件', () {
      container.read(favoritesFilterProvider.notifier).setFilter('col-1');
      expect(container.read(favoritesFilterProvider), 'col-1');
    });

    test('setFilter(null) 恢复为全部', () {
      container.read(favoritesFilterProvider.notifier).setFilter('col-1');
      container.read(favoritesFilterProvider.notifier).setFilter(null);
      expect(container.read(favoritesFilterProvider), isNull);
    });

    test('filter 变更后 favoritesProvider 重新读取列表', () {
      container.read(collectionsProvider.notifier).create('收藏夹A');
      final collectionId = container.read(collectionsProvider).first.id;

      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: '分类问题',
            assistantContent: '分类回答',
            collectionId: collectionId,
          );
      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '未分类问题', assistantContent: '未分类回答');

      // 初始 filter=null，应返回全部
      expect(container.read(favoritesProvider), hasLength(2));

      // 切换到未分类
      container.read(favoritesFilterProvider.notifier).setFilter('');
      expect(container.read(favoritesProvider), hasLength(1));
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '未分类问题',
      );

      // 切换到具体收藏夹
      container.read(favoritesFilterProvider.notifier).setFilter(collectionId);
      expect(container.read(favoritesProvider), hasLength(1));
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '分类问题',
      );
    });
  });

  group('favoriteByIdProvider', () {
    test('filter 选中 collection A 时仍能读取 collection B 的收藏', () {
      // favorites.collection_id 有外键约束，先建两个收藏夹再写入收藏。
      container
          .read(collectionsRepositoryProvider)
          .save(
            FavoriteCollection(
              id: 'col-a',
              name: 'A',
              createdAt: DateTime(2026),
            ),
          );
      container
          .read(collectionsRepositoryProvider)
          .save(
            FavoriteCollection(
              id: 'col-b',
              name: 'B',
              createdAt: DateTime(2026),
            ),
          );
      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: 'B 的问题',
            assistantContent: 'B 的回复',
            collectionId: 'col-b',
          );
      container
          .read(favoritesProvider.notifier)
          .add(
            userMessageContent: 'A 的问题',
            assistantContent: 'A 的回复',
            collectionId: 'col-a',
          );
      final bId = container
          .read(favoritesProvider)
          .firstWhere((f) => f.collectionId == 'col-b')
          .id;

      container.read(favoritesFilterProvider.notifier).setFilter('col-a');
      final favorite = container.read(favoriteByIdProvider(bId));

      expect(favorite, isNotNull);
      expect(favorite!.userMessageContent, 'B 的问题');
      expect(favorite.collectionId, 'col-b');
    });

    test('rename 后 by-ID 标题立即更新', () {
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回复');

      container.read(favoritesProvider.notifier).rename(id, '新标题');

      expect(container.read(favoriteByIdProvider(id))!.title, '新标题');
    });

    test('move 后 by-ID collectionId 立即更新', () {
      // favorites.collection_id 有外键约束，目标收藏夹需先存在。
      container
          .read(collectionsRepositoryProvider)
          .save(
            FavoriteCollection(
              id: 'col-x',
              name: 'X',
              createdAt: DateTime(2026),
            ),
          );
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回复');

      container.read(favoritesProvider.notifier).moveTo(id, 'col-x');

      expect(container.read(favoriteByIdProvider(id))!.collectionId, 'col-x');
    });

    test('remove 后 by-ID 为 null', () {
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回复');

      container.read(favoritesProvider.notifier).remove(id);

      expect(container.read(favoriteByIdProvider(id)), isNull);
    });
  });
}
