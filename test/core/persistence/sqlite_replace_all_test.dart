import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/persistence/sqlite_replace_all.dart';

/// 创建测试用的内存数据库，含一张临时数据表。
sqlite.Database _createTestDb() {
  final db = sqlite.sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON;');
  db.execute('''
    CREATE TABLE test_items (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    );
  ''');
  return db;
}

void main() {
  group('configureSqlitePragmas', () {
    test('enables foreign keys', () {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.close);
      configureSqlitePragmas(db, isInMemory: true);

      final result = db.select('PRAGMA foreign_keys;').single;
      expect(result['foreign_keys'], equals(1));
    });

    test('skips WAL for in-memory database', () {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.close);
      configureSqlitePragmas(db, isInMemory: true);

      // 内存数据库不应启用 WAL（仅对文件数据库有效）
      final journalMode = db.select('PRAGMA journal_mode;').single['journal_mode'];
      expect(journalMode, isNot(equals('wal')));
    });
  });

  group('replaceAllRowsInTable', () {
    test('happy path: replaces existing rows with new set', () {
      final db = _createTestDb();
      addTearDown(db.close);

      // 先插入两条基线数据
      db.execute("INSERT INTO test_items (id, name) VALUES ('a', 'old-a');");
      db.execute("INSERT INTO test_items (id, name) VALUES ('b', 'old-b');");

      // 全量替换为三条新数据
      replaceAllRowsInTable<MapEntry<String, String>>(
        connection: db,
        deleteSql: 'DELETE FROM test_items;',
        insertSql: 'INSERT INTO test_items (id, name) VALUES (?, ?);',
        items: const [
          MapEntry('a', 'new-a'),
          MapEntry('c', 'new-c'),
          MapEntry('d', 'new-d'),
        ],
        buildValues: (item) => [item.key, item.value],
      );

      final rows = db.select('SELECT id, name FROM test_items ORDER BY id;');
      expect(rows.length, equals(3));
      expect(rows[0]['id'], equals('a'));
      expect(rows[0]['name'], equals('new-a'));
      expect(rows[1]['id'], equals('c'));
      expect(rows[1]['name'], equals('new-c'));
      expect(rows[2]['id'], equals('d'));
      expect(rows[2]['name'], equals('new-d'));
    });

    test('rolls back on error: table content unchanged after failure', () {
      final db = _createTestDb();
      addTearDown(db.close);

      // 先插入一条基线数据
      db.execute("INSERT INTO test_items (id, name) VALUES ('baseline', 'baseline-name');");

      // 构造一个会在第二项抛异常的 buildValues，触发事务回滚
      final items = <String>['x1', 'x2'];
      expect(
        () => replaceAllRowsInTable<String>(
          connection: db,
          deleteSql: 'DELETE FROM test_items;',
          insertSql: 'INSERT INTO test_items (id, name) VALUES (?, ?);',
          items: items,
          buildValues: (item) {
            if (item == 'x2') {
              throw StateError('injected failure');
            }
            return [item, item];
          },
        ),
        throwsA(isA<StateError>()),
      );

      // 回滚后，表内容应回到调用前状态：仅剩基线数据，x1 未被写入
      final rows = db.select('SELECT id, name FROM test_items ORDER BY id;');
      expect(rows.length, equals(1));
      expect(rows[0]['id'], equals('baseline'));
      expect(rows[0]['name'], equals('baseline-name'));
    });

    test('empty list clears table', () {
      final db = _createTestDb();
      addTearDown(db.close);

      db.execute("INSERT INTO test_items (id, name) VALUES ('a', 'a-name');");
      db.execute("INSERT INTO test_items (id, name) VALUES ('b', 'b-name');");

      replaceAllRowsInTable<String>(
        connection: db,
        deleteSql: 'DELETE FROM test_items;',
        insertSql: 'INSERT INTO test_items (id, name) VALUES (?, ?);',
        items: const [],
        buildValues: (item) => [item, item],
      );

      final count = db.select('SELECT COUNT(*) AS cnt FROM test_items;').single['cnt'];
      expect(count, equals(0));
    });

    test('inserts into empty table on first call', () {
      final db = _createTestDb();
      addTearDown(db.close);

      replaceAllRowsInTable<MapEntry<String, String>>(
        connection: db,
        deleteSql: 'DELETE FROM test_items;',
        insertSql: 'INSERT INTO test_items (id, name) VALUES (?, ?);',
        items: const [
          MapEntry('a', 'a-name'),
          MapEntry('b', 'b-name'),
        ],
        buildValues: (item) => [item.key, item.value],
      );

      final rows = db.select('SELECT id, name FROM test_items ORDER BY id;');
      expect(rows.length, equals(2));
      expect(rows[0]['id'], equals('a'));
      expect(rows[1]['id'], equals('b'));
    });
  });
}
