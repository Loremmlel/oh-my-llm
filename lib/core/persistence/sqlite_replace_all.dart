import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 配置 SQLite 连接的标准 PRAGMA（外键约束、WAL 模式、忙等待超时）。
///
/// 内存数据库（`:memory:`）跳过 WAL 模式（仅对文件数据库有效）。
void configureSqlitePragmas(sqlite.Database db, {required bool isInMemory}) {
  db.execute('PRAGMA foreign_keys = ON;');
  if (!isInMemory) db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA busy_timeout = 5000;');
}

/// 以”先清空再全量插入”的方式覆盖表内容，统一事务与回滚模板。
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
