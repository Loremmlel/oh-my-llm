import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/collection.dart';
import '../../domain/models/collection_delete_request.dart';
import '../../domain/models/favorite_collection_summary.dart';

/// 必须由 app composition 或测试显式绑定的收藏夹仓库。
final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  throw StateError('CollectionsRepository 尚未由应用组合层绑定');
});

/// 收藏夹的读写仓库接口。
abstract interface class CollectionsRepository {
  /// 返回收藏夹卡片投影列表：系统"未分类"恒置顶，其余按名称稳定排序
  /// （同名按 id tie-break）；每项含归属数量与最近收录时间。
  List<FavoriteCollectionSummary> loadSummaries();

  /// 返回全部收藏夹，排序规则同 [loadSummaries]；供选择器使用。
  List<FavoriteCollection> loadAll();

  /// 保存单个收藏夹（UPSERT：按 id 更新，不触发删除-重建语义）。
  void save(FavoriteCollection collection);

  /// 在同一事务内处置夹内收藏并删除普通收藏夹，返回受影响收藏数。
  ///
  /// [disposition] 决定收藏去向（移动或一并删除）；
  /// 系统"未分类"收藏夹不可删除（ArgumentError）。
  int delete(
    String collectionId, {
    required CollectionDeleteRequest disposition,
  });
}
