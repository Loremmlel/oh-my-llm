import 'app_database.dart';
import 'sqlite_replace_all.dart';

/// 适用于"全量加载 + 全量写入"模式的简单 SQLite 实体仓库。
///
/// 适用于不存在增量查询需求的实体（如设置页的模板、序列等），
/// 只需声明表结构与映射函数即可获得完整的 CRUD 读取能力。
class SqliteEntityRepository<T> {
  const SqliteEntityRepository({
    required this.tableName,
    required this.selectColumns,
    required this.insertColumns,
    required this.insertPlaceholders,
    required this.rowToEntity,
    required this.entityToValues,
    this.orderBy = 'updated_at DESC',
  });

  final String tableName;
  final String selectColumns;
  final String insertColumns;
  final String insertPlaceholders;
  final T Function(Map<String, dynamic> row) rowToEntity;
  final List<Object?> Function(T entity) entityToValues;
  final String orderBy;

  List<T> loadAll(AppDatabase database) {
    final rows = database.connection.select(
      'SELECT $selectColumns FROM $tableName ORDER BY $orderBy;',
    );
    return rows.map(rowToEntity).toList(growable: false);
  }

  Future<void> saveAll(AppDatabase database, List<T> items) async {
    replaceAllRowsInTable(
      connection: database.connection,
      deleteSql: 'DELETE FROM $tableName;',
      insertSql:
          'INSERT INTO $tableName ($insertColumns) VALUES ($insertPlaceholders);',
      items: items,
      buildValues: entityToValues,
    );
  }
}
