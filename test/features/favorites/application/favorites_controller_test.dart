import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
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

  /// 当前可见收藏列表中的普通（非系统）收藏夹 ID 集合。
  Set<String> normalCollectionIds() => container
      .read(collectionsProvider)
      .where((c) => !c.isSystem)
      .map((c) => c.id)
      .toSet();

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
      final collectionId = normalCollectionIds().single;

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
      expect(fav.collectionAssignedAt, fav.createdAt);
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

    test('add/moveTo 的 null 与空串归属归一为系统未分类收藏夹', () {
      final notifier = container.read(favoritesProvider.notifier);
      notifier.add(userMessageContent: '问题甲', assistantContent: '回答甲');
      notifier.add(
        userMessageContent: '问题乙',
        assistantContent: '回答乙',
        collectionId: '',
      );

      final favorites = container.read(favoritesProvider);
      expect(favorites, hasLength(2));
      for (final favorite in favorites) {
        expect(
          favorite.collectionId,
          AppReservedEntities.uncategorizedFavoriteCollectionId,
        );
      }

      final favId = favorites.first.id;
      notifier.moveTo(favId, '');
      expect(container.read(favoritesProvider).first.id, favId);
    });

    test('moveTo 生命周期：移入收藏夹后再移回系统未分类', () {
      container.read(collectionsProvider.notifier).create('目标收藏夹');
      final collectionId = normalCollectionIds().single;

      container
          .read(favoritesProvider.notifier)
          .add(userMessageContent: '问题', assistantContent: '回答');
      final favId = container.read(favoritesProvider).first.id;

      container.read(favoritesProvider.notifier).moveTo(favId, collectionId);
      final moved = container.read(favoritesProvider).first;
      expect(moved.collectionId, collectionId);
      expect(moved.collectionAssignedAt, isNot(moved.createdAt));

      container.read(favoritesProvider.notifier).moveTo(favId, null);
      expect(
        container.read(favoritesProvider).first.collectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
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
      expect(normalCollectionIds(), [id]);
      expect(
        container.read(collectionsProvider).firstWhere((c) => c.id == id).name,
        '我的笔记',
      );

      notifier.rename(id, '  新名字  ');
      expect(normalCollectionIds(), [id]);
      expect(
        container.read(collectionsProvider).firstWhere((c) => c.id == id).name,
        '新名字',
      );

      notifier.delete(id);
      expect(normalCollectionIds(), isEmpty);
      // 系统收藏夹始终保留。
      expect(container.read(collectionsProvider), hasLength(1));
    });

    test('rename/delete 不存在的 ID 为 no-op，既有收藏夹不变', () {
      final notifier = container.read(collectionsProvider.notifier);
      final id = notifier.create('保留');

      notifier.rename('nonexistent', '名字');
      expect(normalCollectionIds(), [id]);

      notifier.delete('nonexistent');
      expect(normalCollectionIds(), [id]);
    });

    test('创建名为未分类的收藏夹被拒绝并归位系统收藏夹', () {
      final notifier = container.read(collectionsProvider.notifier);

      final id = notifier.create(' 未分类 ');
      expect(id, AppReservedEntities.uncategorizedFavoriteCollectionId);
      // 没有创建新行，只有播种的系统收藏夹。
      expect(container.read(collectionsProvider), hasLength(1));
      expect(container.read(collectionsProvider).single.isSystem, isTrue);
    });

    test('系统收藏夹不可重命名也不可删除，普通夹不可改名为未分类', () {
      final notifier = container.read(collectionsProvider.notifier);
      final normalId = notifier.create('工作笔记');
      final systemId = AppReservedEntities.uncategorizedFavoriteCollectionId;

      notifier.rename(systemId, '别的名字');
      notifier.delete(systemId);
      expect(
        container
            .read(collectionsProvider)
            .firstWhere((c) => c.id == systemId)
            .name,
        '未分类',
      );

      notifier.rename(normalId, '未分类');
      expect(
        container
            .read(collectionsProvider)
            .firstWhere((c) => c.id == normalId)
            .name,
        '工作笔记',
      );
    });
  });

  group('FavoritesFilterNotifier', () {
    test('filter 变更后 favoritesProvider 重新读取列表', () {
      container.read(collectionsProvider.notifier).create('收藏夹A');
      final collectionId = normalCollectionIds().single;

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

      // 切换到未分类：空串 sentinel 映射到系统收藏夹
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
