import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import '../domain/models/collection.dart';
import '../application/ports/collections_repository.dart';

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
    // UPSERT 而非 INSERT OR REPLACE：重命名不能触发删除-重建语义，
    // 否则 v14 的 RESTRICT 外键会把收藏一起带走。
    _database.connection.execute(
      'INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = excluded.name;',
      [collection.id, collection.name, collection.createdAt.toIso8601String()],
    );
  }

  @override
  void delete(String collectionId) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId) {
      throw ArgumentError('系统"未分类"收藏夹不可删除', 'collectionId');
    }
    final connection = _database.connection;
    connection.execute('BEGIN;');
    try {
      // 临时兼容：v14 外键为 RESTRICT，删夹前必须先把收藏移入系统夹。
      // Task 7 将以 typed CollectionDeleteRequest 显式表达移动/删除语义。
      connection.execute(
        'UPDATE favorites SET collection_id = ?, collection_assigned_at = ? '
        'WHERE collection_id = ?;',
        [
          AppReservedEntities.uncategorizedFavoriteCollectionId,
          DateTime.now().toIso8601String(),
          collectionId,
        ],
      );
      connection.execute('DELETE FROM collections WHERE id = ?;', [
        collectionId,
      ]);
      connection.execute('COMMIT;');
    } catch (_) {
      connection.execute('ROLLBACK;');
      rethrow;
    }
  }

  FavoriteCollection _rowToCollection(Map<String, dynamic> row) {
    return FavoriteCollection(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
