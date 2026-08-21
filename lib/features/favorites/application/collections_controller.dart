import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'ports/collections_repository.dart';
import '../domain/models/collection.dart';
import '../domain/models/collection_delete_request.dart';

/// 收藏夹状态 Provider。
final collectionsProvider =
    NotifierProvider<CollectionsController, List<FavoriteCollection>>(
      CollectionsController.new,
    );

/// 收藏夹管理控制器。
///
/// 维护全部收藏夹列表，支持新建、重命名与删除（删除时内部收藏移入未分类）。
class CollectionsController extends Notifier<List<FavoriteCollection>> {
  CollectionsRepository get _repo => ref.read(collectionsRepositoryProvider);

  @override
  List<FavoriteCollection> build() {
    return _loadVisibleCollections();
  }

  /// 新建一个收藏夹并返回其 ID。
  ///
  /// 名称与系统"未分类"（trim 后精确比较）冲突时不创建新行，
  /// 返回系统收藏夹 ID——旧调用方拿到的仍是可用的归属目标；
  /// Task 9/11 的 dialog inline 报错落地后调用方不再触发该分支。
  String create(String name) {
    final trimmed = name.trim();
    if (_isReservedName(trimmed)) {
      return AppReservedEntities.uncategorizedFavoriteCollectionId;
    }
    final collection = FavoriteCollection(
      id: generateEntityId(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    _repo.save(collection);
    state = _loadVisibleCollections();
    return collection.id;
  }

  /// 重命名指定收藏夹。
  ///
  /// 系统收藏夹不可重命名；新名称与"未分类"冲突时保持不变。
  void rename(String collectionId, String newName) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId) {
      return;
    }
    final existing = state.where((c) => c.id == collectionId).firstOrNull;
    if (existing == null || _isReservedName(newName.trim())) {
      return;
    }
    _repo.save(existing.copyWith(name: newName.trim()));
    state = _loadVisibleCollections();
  }

  /// 删除指定收藏夹；内部收藏由 repository 在同一事务内移入未分类。
  void delete(String collectionId) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId) {
      return;
    }
    _repo.delete(
      collectionId,
      disposition: CollectionDeleteRequest.moveItemsTo(
        targetCollectionId:
            AppReservedEntities.uncategorizedFavoriteCollectionId,
        assignedAt: DateTime.now(),
      ),
    );
    state = _loadVisibleCollections();
  }

  /// 读取对 UI 可见的收藏夹列表。
  ///
  /// 历史数据中可能残留名为"未分类"的普通行（v13 时代允许自由命名）；
  /// 系统行已承担该语义，同名普通行在此过滤，保证"未分类"只出现一次。
  List<FavoriteCollection> _loadVisibleCollections() {
    return _repo
        .loadAll()
        .where(
          (c) =>
              c.isSystem ||
              c.name.trim() !=
                  AppReservedEntities.uncategorizedFavoriteCollectionName,
        )
        .toList(growable: false);
  }

  bool _isReservedName(String trimmedName) {
    return trimmedName ==
        AppReservedEntities.uncategorizedFavoriteCollectionName;
  }
}
