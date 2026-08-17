import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/persistence/app_database.dart';

void main() {
  group('AppDatabase 当前 schema 基线', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() {
      database.close();
    });

    test('全新内存数据库直接创建当前完整 schema 并标记 user_version', () {
      final version =
          database.connection
                  .select('PRAGMA user_version;')
                  .single['user_version']
              as int;
      expect(version, greaterThanOrEqualTo(AppDatabase.currentSchemaVersion));
    });

    test('创建全部关键业务表', () {
      final tables = _tableNames(database);
      expect(
        tables,
        containsAll([
          'conversations',
          'messages',
          'conversation_branch_selections',
          'preset_prompts',
          'fixed_prompt_sequences',
          'collections',
          'favorites',
          'template_prompts',
          'memory_prompts',
          'conversation_checkpoints',
        ]),
      );
    });

    test('conversations 表包含 selected_preset_prompt_id 列', () {
      final columns = database.connection
          .select('PRAGMA table_info(conversations);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, contains('selected_preset_prompt_id'));
    });

    test('preset_prompts 表不含 system_prompt 列', () {
      final columns = database.connection
          .select('PRAGMA table_info(preset_prompts);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, isNot(contains('system_prompt')));
    });

    test('favorites.title 列默认为 NULL', () {
      database.connection.execute(
        "INSERT INTO favorites (id, user_message_content, assistant_content, created_at) "
        "VALUES ('fav-1', 'hello', 'world', '2025-01-01T00:00:00.000');",
      );

      final rows = database.connection.select(
        'SELECT title FROM favorites WHERE id = ?;',
        ['fav-1'],
      );
      expect(rows.length, 1);
      expect(rows.first['title'], isNull);
    });

    test('messages.finish_reason 列默认为 NULL', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'user', 'hello', '2026-01-01');
      ''');

      final rows = database.connection.select(
        'SELECT finish_reason FROM messages WHERE id = ?;',
        ['m1'],
      );
      expect(rows.length, 1);
      expect(rows.first['finish_reason'], isNull);
    });

    test('删除 conversation 后清理消息、分支选择和检查点', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'user', 'hello', '2026-01-01');
      ''');
      database.connection.execute('''
        INSERT INTO conversation_branch_selections (conversation_id, parent_id, child_id)
        VALUES ('c1', 'root', 'm1');
      ''');
      database.connection.execute('''
        INSERT INTO conversation_checkpoints (
          id, conversation_id, title, content, created_at
        ) VALUES ('cp-1', 'c1', '检查点 1', '摘要', '2026-01-01');
      ''');

      database.connection.execute("DELETE FROM conversations WHERE id = 'c1';");

      expect(
        database.connection.select(
          "SELECT * FROM messages WHERE conversation_id = 'c1';",
        ),
        isEmpty,
      );
      expect(
        database.connection.select(
          "SELECT * FROM conversation_branch_selections WHERE conversation_id = 'c1';",
        ),
        isEmpty,
      );
      expect(
        database.connection.select(
          "SELECT * FROM conversation_checkpoints WHERE conversation_id = 'c1';",
        ),
        isEmpty,
      );
    });

    test('删除 collection 后 favorites.collection_id 置为 NULL', () {
      database.connection.execute('''
        INSERT INTO collections (id, name, created_at)
        VALUES ('col-1', '测试收藏夹', '2026-01-01');
      ''');
      database.connection.execute('''
        INSERT INTO favorites (
          id, collection_id, user_message_content, assistant_content, created_at
        ) VALUES ('f1', 'col-1', '问题', '回答', '2026-01-01');
      ''');

      database.connection.execute(
        "DELETE FROM collections WHERE id = 'col-1';",
      );

      final row = database.connection
          .select("SELECT collection_id FROM favorites WHERE id = 'f1';")
          .single;
      expect(row['collection_id'], isNull);
    });
  });

  group('AppDatabase 版本边界打开行为', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('appdb-version-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// 构造一个 user_version 为 [version] 的非空文件数据库。
    ///
    /// 建一张最小表代表旧版/未来版 schema，版本差异由 user_version 表达。
    String createDbFile(String name, int version) {
      final path = '${tempDir.path}${Platform.pathSeparator}$name';
      final db = sqlite.sqlite3.open(path);
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          reasoning_effort TEXT NOT NULL
        );
      ''');
      db.execute('PRAGMA user_version = $version;');
      db.close();
      return path;
    }

    test('已处于当前版本的数据库重新打开时不改动数据', () {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}test_v13.db';

      // 首次打开用当前代码建出完整当前 schema
      final created = AppDatabase.forPath(dbPath);
      created.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      created.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'user', '你好', '2026-01-01');
      ''');
      expect(
        created.connection.select('PRAGMA user_version;').single['user_version']
            as int,
        greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
      );
      created.close();

      // 再次打开：当前版本库直接可用，不重建 schema、不丢数据
      final reopened = AppDatabase.forPath(dbPath);
      addTearDown(reopened.close);

      expect(
        reopened.connection
                .select('PRAGMA user_version;')
                .single['user_version']
            as int,
        greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
      );
      final row = reopened.connection
          .select("SELECT content FROM messages WHERE id = 'm1';")
          .single;
      expect(row['content'], equals('你好'));
    });

    test('低于当前基线的旧版数据库在打开时显式拒绝', () {
      for (final version in [1, 8, 12]) {
        final path = createDbFile('legacy_$version.db', version);
        // 打开即抛异常：连接不会交给任何仓库层在旧 schema 上执行查询
        expect(
          () => AppDatabase.forPath(path),
          throwsA(isA<AppDatabaseSchemaVersionException>()),
        );
      }
    });

    test('高于当前基线的未来版本数据库显式拒绝打开', () {
      final path = createDbFile('future_14.db', 14);
      // 旧代码不静默读写更新版本应用创建的 schema
      expect(
        () => AppDatabase.forPath(path),
        throwsA(isA<AppDatabaseSchemaVersionException>()),
      );
    });
  });
}

List<String> _tableNames(AppDatabase database) {
  return database.connection
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      )
      .map((row) => row['name'] as String)
      .toList();
}
