import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/collection.dart';
import 'sqlite_collections_repository.dart';

final collectionsRepositoryProvider = Provider<CollectionsRepository>(
  (ref) => SqliteCollectionsRepository(ref.watch(appDatabaseProvider)),
);

/// 收藏夹的读写仓库接口。
abstract interface class CollectionsRepository {
  /// 按创建时间升序返回全部收藏夹。
  List<FavoriteCollection> loadAll();

  /// 保存单个收藏夹（INSERT OR REPLACE）。
  void save(FavoriteCollection collection);

  /// 删除指定收藏夹。
  void delete(String collectionId);
}
