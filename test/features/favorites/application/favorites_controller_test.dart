import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';

void main() {
  group('FavoritesController', () {
    late AppDatabase database;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
    });

    tearDown(() {
      container.dispose();
      database.close();
    });

    test('starts empty', () {
      expect(container.read(favoritesProvider), isEmpty);
    });

    test('add inserts a favorite into the list', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '用户消息',
        assistantContent: '模型回复',
      );

      final favorites = container.read(favoritesProvider);
      expect(favorites.length, 1);
      expect(favorites.first.userMessageContent, '用户消息');
      expect(favorites.first.assistantContent, '模型回复');
      expect(favorites.first.collectionId, isNull);
    });

    test('add stores sourceConversationId and title', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '问题',
        assistantContent: '回答',
        sourceConversationId: 'conv-1',
        sourceConversationTitle: '对话标题',
      );

      final fav = container.read(favoritesProvider).first;
      expect(fav.sourceConversationId, 'conv-1');
      expect(fav.sourceConversationTitle, '对话标题');
    });

    test('add with collectionId stores the collection association', () {
      // First create a collection
      container.read(collectionsProvider.notifier).create('测试收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
        userMessageContent: '有分类的问题',
        assistantContent: '有分类的回复',
        collectionId: collectionId,
      );

      expect(container.read(favoritesProvider).first.collectionId, collectionId);
    });

    test('remove deletes the favorite from the list', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '要删除的消息',
        assistantContent: '要删除的回复',
      );

      final id = container.read(favoritesProvider).first.id;
      container.read(favoritesProvider.notifier).remove(id);

      expect(container.read(favoritesProvider), isEmpty);
    });

    test('moveTo changes the collection of a favorite', () {
      container.read(collectionsProvider.notifier).create('目标收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
        userMessageContent: '要移动的问题',
        assistantContent: '要移动的回复',
      );

      final favId = container.read(favoritesProvider).first.id;
      container.read(favoritesProvider.notifier).moveTo(favId, collectionId);

      expect(
        container.read(favoritesProvider).first.collectionId,
        collectionId,
      );
    });

    test('moveTo with null moves favorite to uncategorized', () {
      container.read(collectionsProvider.notifier).create('原来的收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
        userMessageContent: '要移动的问题',
        assistantContent: '要移动的回复',
        collectionId: collectionId,
      );

      final favId = container.read(favoritesProvider).first.id;
      container.read(favoritesProvider.notifier).moveTo(favId, null);

      expect(container.read(favoritesProvider).first.collectionId, isNull);
    });

    test('isFavorited returns true when content is already favorited', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '问题',
        assistantContent: '已收藏的内容',
      );

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

    test('filter null shows all favorites', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '问题1',
        assistantContent: '回复1',
        collectionId: null,
      );
      container.read(collectionsProvider.notifier).create('收藏夹A');
      final colId = container.read(collectionsProvider).first.id;
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '问题2',
        assistantContent: '回复2',
        collectionId: colId,
      );

      container.read(favoritesFilterProvider.notifier).setFilter(null);

      expect(container.read(favoritesProvider).length, 2);
    });

    test('filter empty string shows only uncategorized favorites', () {
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '未分类问题',
        assistantContent: '未分类回复',
        collectionId: null,
      );
      container.read(collectionsProvider.notifier).create('收藏夹A');
      final colId = container.read(collectionsProvider).first.id;
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '有分类问题',
        assistantContent: '有分类回复',
        collectionId: colId,
      );

      container.read(favoritesFilterProvider.notifier).setFilter('');

      expect(container.read(favoritesProvider).length, 1);
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '未分类问题',
      );
    });

    test('filter by collection id shows only matching favorites', () {
      container.read(collectionsProvider.notifier).create('收藏夹A');
      final colId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
        userMessageContent: '收藏夹内问题',
        assistantContent: '收藏夹内回复',
        collectionId: colId,
      );
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '未分类问题',
        assistantContent: '未分类回复',
      );

      container.read(favoritesFilterProvider.notifier).setFilter(colId);

      expect(container.read(favoritesProvider).length, 1);
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '收藏夹内问题',
      );
    });
  });

  group('CollectionsController', () {
    late AppDatabase database;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
    });

    tearDown(() {
      container.dispose();
      database.close();
    });

    test('starts empty', () {
      expect(container.read(collectionsProvider), isEmpty);
    });

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

    test('deleting collection moves its favorites to uncategorized', () {
      container.read(collectionsProvider.notifier).create('收藏夹');
      final colId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
        userMessageContent: '属于收藏夹的问题',
        assistantContent: '属于收藏夹的回复',
        collectionId: colId,
      );

      expect(container.read(favoritesProvider).first.collectionId, colId);

      container.read(collectionsProvider.notifier).delete(colId);

      // Toggling the filter forces FavoritesController.build() to re-query the DB,
      // picking up the ON DELETE SET NULL cascade that cleared collection_id.
      container.read(favoritesFilterProvider.notifier).setFilter('');
      container.read(favoritesFilterProvider.notifier).setFilter(null);
      expect(
        container.read(favoritesProvider).first.collectionId,
        isNull,
      );
    });

    test('rename nonexistent id is silently ignored', () {
      container.read(collectionsProvider.notifier).rename('nonexistent', '名字');

      expect(container.read(collectionsProvider), isEmpty);
    });
  });
}
