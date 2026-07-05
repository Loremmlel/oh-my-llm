import '../../../core/persistence/app_database.dart';
import '../domain/models/collection.dart';
import 'collections_repository.dart';

/// 收藏夹的 SQLite 读写仓库。
class SqliteCollectionsRepository implements CollectionsRepository {
  const SqliteCollectionsRepository(this._database);

  final AppDatabase _database;

  @override
  List<FavoriteCollection> loadAll() {
    final rows = _database.connection.select(
      'SELECT id, name, created_at FROM collections ORDER BY created_at ASC;',
    );
    return rows.map(_rowToCollection).toList(growable: false);
  }

  @override
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

  @override
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
