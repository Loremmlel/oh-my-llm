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

    test('add inserts a favorite with all fields into the list', () {
      container.read(collectionsProvider.notifier).create('测试收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container.read(favoritesProvider.notifier).add(
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
      container.read(favoritesProvider.notifier).add(
        userMessageContent: '要删除的消息',
        assistantContent: '要删除的回复',
      );

      final id = container.read(favoritesProvider).first.id;
      container.read(favoritesProvider.notifier).remove(id);

      expect(container.read(favoritesProvider), isEmpty);
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
  });
}
