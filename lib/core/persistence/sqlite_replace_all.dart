import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 以“先清空再全量插入”的方式覆盖表内容，统一事务与回滚模板。
void replaceAllRowsInTable<T>({
  required sqlite.Database connection,
  required String deleteSql,
  required String insertSql,
  required Iterable<T> items,
  required List<Object?> Function(T item) buildValues,
}) {
  connection.execute('BEGIN;');
  try {
    connection.execute(deleteSql);
    final statement = connection.prepare(insertSql);
    try {
      for (final item in items) {
        statement.execute(buildValues(item));
      }
    } finally {
      statement.close();
    }
    connection.execute('COMMIT;');
  } catch (_) {
    connection.execute('ROLLBACK;');
    rethrow;
  }
}
