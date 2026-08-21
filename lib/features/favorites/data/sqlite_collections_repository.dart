import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import '../domain/models/collection.dart';
import '../domain/models/collection_delete_request.dart';
import '../domain/models/favorite_collection_summary.dart';
import '../application/ports/collections_repository.dart';

/// 收藏夹的 SQLite 读写仓库。
class SqliteCollectionsRepository implements CollectionsRepository {
  const SqliteCollectionsRepository(this._database);

  /// 系统收藏夹在卡片列表中的固定置顶排序键。
  static const _systemOrderKey = 0;
  static const _normalOrderKey = 1;

  final AppDatabase _database;

  @override
  List<FavoriteCollectionSummary> loadSummaries() {
    // 系统夹恒置顶，其余按名称稳定排序（同名按 id tie-break）；
    // 空夹的最近收录时间回退收藏夹创建时间。
    final rows = _database.connection.select(
      '''
      SELECT c.id, c.name, c.created_at,
             COUNT(f.id) AS item_count,
             COALESCE(MAX(f.collection_assigned_at), c.created_at) AS recent_assigned_at
      FROM collections c
      LEFT JOIN favorites f ON f.collection_id = c.id
      GROUP BY c.id, c.name, c.created_at
      ORDER BY CASE WHEN c.id = ? THEN $_systemOrderKey ELSE $_normalOrderKey END,
               c.name, c.id;
    ''',
      [AppReservedEntities.uncategorizedFavoriteCollectionId],
    );

    return rows
        .map(
          (row) => FavoriteCollectionSummary(
            collection: _rowToCollection(row),
            itemCount: row['item_count'] as int,
            recentAssignedAt: DateTime.parse(
              row['recent_assigned_at'] as String,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  List<FavoriteCollection> loadAll() {
    final rows = _database.connection.select(
      '''
      SELECT c.id, c.name, c.created_at
      FROM collections c
      ORDER BY CASE WHEN c.id = ? THEN $_systemOrderKey ELSE $_normalOrderKey END,
               c.name, c.id;
    ''',
      [AppReservedEntities.uncategorizedFavoriteCollectionId],
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
  int delete(
    String collectionId, {
    required CollectionDeleteRequest disposition,
  }) {
    if (collectionId == AppReservedEntities.uncategorizedFavoriteCollectionId) {
      throw ArgumentError('系统"未分类"收藏夹不可删除', 'collectionId');
    }
    final connection = _database.connection;
    connection.execute('BEGIN;');
    try {
      final affected = switch (disposition) {
        MoveItemsOnCollectionDelete(
          :final targetCollectionId,
          :final assignedAt,
        ) =>
          _deleteWithMove(
            connection,
            collectionId,
            targetCollectionId: targetCollectionId,
            assignedAt: assignedAt,
          ),
        DeleteItemsOnCollectionDelete() => _deleteWithItems(
          connection,
          collectionId,
        ),
      };
      connection.execute('COMMIT;');
      return affected;
    } catch (_) {
      connection.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// 移动处置：先转移收藏再删夹；目标必须存在且不得等于被删夹本身。
  int _deleteWithMove(
    sqlite.Database connection,
    String collectionId, {
    required String targetCollectionId,
    required DateTime assignedAt,
  }) {
    if (targetCollectionId == collectionId) {
      throw ArgumentError('移动目标不能是被删除的收藏夹本身', 'targetCollectionId');
    }
    final targetExists = connection.select(
      'SELECT 1 FROM collections WHERE id = ? LIMIT 1;',
      [targetCollectionId],
    ).isNotEmpty;
    if (!targetExists) {
      throw ArgumentError('移动目标收藏夹不存在', 'targetCollectionId');
    }

    connection.execute(
      'UPDATE favorites SET collection_id = ?, collection_assigned_at = ? '
      'WHERE collection_id = ?;',
      [targetCollectionId, assignedAt.toIso8601String(), collectionId],
    );
    final affected =
        connection.select('SELECT changes() AS c;').single['c'] as int;
    connection.execute('DELETE FROM collections WHERE id = ?;', [collectionId]);
    return affected;
  }

  /// 危险处置：夹内收藏一并删除。
  int _deleteWithItems(sqlite.Database connection, String collectionId) {
    connection.execute('DELETE FROM favorites WHERE collection_id = ?;', [
      collectionId,
    ]);
    final affected =
        connection.select('SELECT changes() AS c;').single['c'] as int;
    connection.execute('DELETE FROM collections WHERE id = ?;', [collectionId]);
    return affected;
  }

  FavoriteCollection _rowToCollection(Map<String, dynamic> row) {
    return FavoriteCollection(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
