import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../data/sqlite_collections_repository.dart';
import '../domain/models/collection.dart';

/// 收藏夹状态 Provider。
final collectionsProvider =
    NotifierProvider<CollectionsController, List<FavoriteCollection>>(
      CollectionsController.new,
    );

/// 收藏夹管理控制器。
///
/// 维护全部收藏夹列表，支持新建、重命名与删除（删除时内部收藏移入未分类）。
class CollectionsController extends Notifier<List<FavoriteCollection>> {
  SqliteCollectionsRepository get _repo =>
      ref.read(collectionsRepositoryProvider);

  @override
  List<FavoriteCollection> build() {
    return _repo.loadAll();
  }

  /// 新建一个收藏夹并返回其 ID。
  String create(String name) {
    final collection = FavoriteCollection(
      id: generateEntityId(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    _repo.save(collection);
    state = _repo.loadAll();
    return collection.id;
  }

  /// 重命名指定收藏夹。
  void rename(String collectionId, String newName) {
    final existing = state.where((c) => c.id == collectionId).firstOrNull;
    if (existing == null) {
      return;
    }
    _repo.save(existing.copyWith(name: newName.trim()));
    state = _repo.loadAll();
  }

  /// 删除指定收藏夹；内部收藏因 ON DELETE SET NULL 自动移入未分类。
  void delete(String collectionId) {
    _repo.delete(collectionId);
    state = _repo.loadAll();
  }
}
