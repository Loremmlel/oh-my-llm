import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/collection.dart';

/// 必须由 app composition 或测试显式绑定的收藏夹仓库。
final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  throw StateError('CollectionsRepository 尚未由应用组合层绑定');
});

/// 收藏夹的读写仓库接口。
abstract interface class CollectionsRepository {
  /// 按创建时间升序返回全部收藏夹。
  List<FavoriteCollection> loadAll();

  /// 保存单个收藏夹（INSERT OR REPLACE）。
  void save(FavoriteCollection collection);

  /// 删除指定收藏夹。
  void delete(String collectionId);
}
