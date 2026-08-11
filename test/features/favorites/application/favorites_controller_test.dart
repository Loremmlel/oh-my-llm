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
            sourceAssistantMessageId: 'msg-42',
            collectionId: collectionId,
          );

      final fav = container.read(favoritesProvider).first;
      expect(fav.userMessageContent, '用户消息');
      expect(fav.assistantContent, '模型回复');
      expect(fav.sourceConversationId, 'conv-1');
      expect(fav.sourceConversationTitle, '对话标题');
      expect(fav.sourceAssistantMessageId, 'msg-42');
      expect(fav.collectionId, collectionId);
    });

    test('isFavorited/remove 生命周期：收藏后可查、移除后清空、重复移除无副作用', () {
      final notifier = container.read(favoritesProvider.notifier);
      notifier.add(userMessageContent: '问题', assistantContent: '已收藏的内容');

      expect(notifier.isFavorited('已收藏的内容'), isTrue);

      final id = container.read(favoritesProvider).first.id;
      notifier.remove(id);

      expect(container.read(favoritesProvider), isEmpty);
      expect(notifier.isFavorited('已收藏的内容'), isFalse);

      // 移除不存在的 id 后状态保持不变
      notifier.remove('nonexistent');
      expect(container.read(favoritesProvider), isEmpty);
    });

    test('moveTo 生命周期：移入收藏夹后再移回未分类', () {
      container.read(collectionsProvider.notifier).create('目标收藏夹');
      final collectionId = container.read(collectionsProvider).first.id;

      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回答');
      final favId = container.read(favoritesProvider).first.id;

      container.read(favoritesProvider.notifier).moveTo(favId, collectionId);
      expect(
        container.read(favoritesProvider).first.collectionId,
        collectionId,
      );

      container.read(favoritesProvider.notifier).moveTo(favId, null);
      expect(container.read(favoritesProvider).first.collectionId, isNull);
    });

    test('rename 生命周期：设置自定义标题后清除', () {
      final id = container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '用户消息', assistantContent: '回复');

      container.read(favoritesProvider.notifier).rename(id, '新标题');
      expect(
        container.read(favoritesProvider).firstWhere((f) => f.id == id).title,
        '新标题',
      );

      container.read(favoritesProvider.notifier).rename(id, null);
      expect(
        container.read(favoritesProvider).firstWhere((f) => f.id == id).title,
        isNull,
      );
    });
  });

  group('CollectionsController', () {
    test('create/rename/delete 生命周期：名称去空白、ID 稳定、删除清空', () {
      final notifier = container.read(collectionsProvider.notifier);

      final id = notifier.create('  我的笔记  ');
      expect(id, isNotEmpty);
      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).first.id, id);
      expect(container.read(collectionsProvider).first.name, '我的笔记');

      notifier.rename(id, '  新名字  ');
      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).first.id, id);
      expect(container.read(collectionsProvider).first.name, '新名字');

      notifier.delete(id);
      expect(container.read(collectionsProvider), isEmpty);
    });

    test('rename/delete 不存在的 ID 为 no-op，既有收藏夹不变', () {
      final notifier = container.read(collectionsProvider.notifier);
      final id = notifier.create('保留');

      notifier.rename('nonexistent', '名字');
      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).first.id, id);

      notifier.delete('nonexistent');
      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).first.id, id);
    });
  });

  group('FavoritesFilterNotifier', () {
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

      final filter = container.read(favoritesFilterProvider.notifier);

      // filter=null 时返回全部
      expect(container.read(favoritesProvider), hasLength(2));

      // 切换到未分类（空串）
      filter.setFilter('');
      expect(container.read(favoritesProvider), hasLength(1));
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '未分类问题',
      );

      // 切换到具体收藏夹
      filter.setFilter(collectionId);
      expect(container.read(favoritesProvider), hasLength(1));
      expect(
        container.read(favoritesProvider).first.userMessageContent,
        '分类问题',
      );

      // 回到 null 恢复全部
      filter.setFilter(null);
      expect(container.read(favoritesProvider), hasLength(2));
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

    test('rename/move/remove 后 by-ID 状态同步更新', () {
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

      container.read(favoritesProvider.notifier).rename(id, '新标题');
      expect(container.read(favoriteByIdProvider(id))!.title, '新标题');

      container.read(favoritesProvider.notifier).moveTo(id, 'col-x');
      expect(container.read(favoriteByIdProvider(id))!.collectionId, 'col-x');

      container.read(favoritesProvider.notifier).remove(id);
      expect(container.read(favoriteByIdProvider(id)), isNull);
    });
  });
}
