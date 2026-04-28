import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/collection.dart';

/// 收藏夹 SQLite 仓库 Provider。
final collectionsRepositoryProvider = Provider<SqliteCollectionsRepository>(
  (ref) => SqliteCollectionsRepository(ref.watch(appDatabaseProvider)),
);

/// 收藏夹的 SQLite 读写仓库。
class SqliteCollectionsRepository {
  const SqliteCollectionsRepository(this._database);

  final AppDatabase _database;

  /// 按创建时间升序返回全部收藏夹。
  List<FavoriteCollection> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, name, created_at FROM collections ORDER BY created_at ASC;',
    );
    return rows.map(_rowToCollection).toList(growable: false);
  }

  /// 保存单个收藏夹（INSERT OR REPLACE）。
  void save(FavoriteCollection collection) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO collections (id, name, created_at) VALUES (?, ?, ?);',
      [
        collection.id,
        collection.name,
        collection.createdAt.toIso8601String(),
      ],
    );
  }

  /// 删除指定收藏夹；内部收藏的 collection_id 因 ON DELETE SET NULL 自动置空。
  void delete(String collectionId) {
    _database.connection.execute(
      'DELETE FROM collections WHERE id = ?;',
      [collectionId],
    );
  }

  FavoriteCollection _rowToCollection(Map<String, dynamic> row) {
    return FavoriteCollection(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
