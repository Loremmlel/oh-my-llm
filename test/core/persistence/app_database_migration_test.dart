import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/persistence/app_database.dart';

void main() {
  group('AppDatabase migration', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() {
      database.close();
    });

    test('user_version 在迁移完成后为 10', () {
      final version =
          database.connection
                  .select('PRAGMA user_version;')
                  .single['user_version']
              as int;
      expect(version, greaterThanOrEqualTo(10));
    });

    test('创建关键业务表', () {
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

  // ────────────────────────────────────────────
  // V9 迁移：从旧版 v8 数据库升级
  // ────────────────────────────────────────────
  group('V9 migration from legacy v8', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8-migration-test-');
      dbPath = '${tempDir.path}${Platform.pathSeparator}migration.sqlite';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// 构造一个 v8 旧版数据库：preset_prompts 表含 system_prompt 列。
    sqlite.Database createLegacyV8Db() {
      final db = sqlite.sqlite3.open(dbPath);
      db.execute('PRAGMA foreign_keys = ON;');
      // 仅创建迁移所需的最小表结构（旧版形态）
      db.execute('''
        CREATE TABLE preset_prompts (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          messages_json TEXT NOT NULL DEFAULT '[]',
          system_prompt TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL
        );
      ''');
      db.execute('PRAGMA user_version = 8;');
      return db;
    }

    test('merges non-empty system_prompt into messages_json and drops column', () {
      // 行 A：system_prompt 非空 + messages_json 无 system 消息 → 应被合并
      final messagesA = [
        {'id': 'u1', 'role': 'user', 'title': 'user', 'content': '你好', 'placement': 'before', 'enabled': true},
      ];
      // 行 B：system_prompt 非空 + messages_json 已有 system 消息 → 应跳过
      final messagesB = [
        {'id': 's0', 'role': 'system', 'title': 'system', 'content': '已有系统', 'placement': 'before', 'enabled': true},
        {'id': 'u2', 'role': 'user', 'title': 'user', 'content': '你好B', 'placement': 'before', 'enabled': true},
      ];
      // 行 C：system_prompt 为空 → 不动
      final messagesC = [
        {'id': 'u3', 'role': 'user', 'title': 'user', 'content': '你好C', 'placement': 'before', 'enabled': true},
      ];

      final legacyDb = createLegacyV8Db();
      legacyDb.execute(
        "INSERT INTO preset_prompts (id, name, messages_json, system_prompt, updated_at) "
        "VALUES ('a', 'A', ?, '你是助手', '2026-01-01');",
        [jsonEncode(messagesA)],
      );
      legacyDb.execute(
        "INSERT INTO preset_prompts (id, name, messages_json, system_prompt, updated_at) "
        "VALUES ('b', 'B', ?, '你是助手B', '2026-01-01');",
        [jsonEncode(messagesB)],
      );
      legacyDb.execute(
        "INSERT INTO preset_prompts (id, name, messages_json, system_prompt, updated_at) "
        "VALUES ('c', 'C', ?, '', '2026-01-01');",
        [jsonEncode(messagesC)],
      );
      legacyDb.close();

      // 重新打开同一文件，触发 _migrate → _migrateV9 的 else 分支
      final migrated = AppDatabase.forPath(dbPath);
      addTearDown(migrated.close);

      // user_version 升到 >= 10
      final version = migrated.connection
          .select('PRAGMA user_version;')
          .single['user_version'] as int;
      expect(version, greaterThanOrEqualTo(10));

      // system_prompt 列已被 DROP
      final columns = migrated.connection
          .select('PRAGMA table_info(preset_prompts);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, isNot(contains('system_prompt')));

      // 行 A：system_prompt 被合并到 messages_json 头部
      final rowA = migrated.connection
          .select("SELECT messages_json FROM preset_prompts WHERE id = 'a';")
          .single;
      final decodedA = jsonDecode(rowA['messages_json'] as String) as List;
      expect(decodedA.length, equals(2));
      expect(decodedA[0]['role'], equals('system'));
      expect(decodedA[0]['content'], equals('你是助手'));
      expect(decodedA[1]['role'], equals('user'));

      // 行 B：已有 system 消息，未被重复合并
      final rowB = migrated.connection
          .select("SELECT messages_json FROM preset_prompts WHERE id = 'b';")
          .single;
      final decodedB = jsonDecode(rowB['messages_json'] as String) as List;
      expect(decodedB.length, equals(2));
      expect(decodedB[0]['content'], equals('已有系统'));
      expect(decodedB[1]['role'], equals('user'));

      // 行 C：system_prompt 为空，messages_json 不变
      final rowC = migrated.connection
          .select("SELECT messages_json FROM preset_prompts WHERE id = 'c';")
          .single;
      final decodedC = jsonDecode(rowC['messages_json'] as String) as List;
      expect(decodedC.length, equals(1));
      expect(decodedC[0]['role'], equals('user'));
    });

    test('handles legacy db with empty preset_prompts table', () {
      // 旧库无任何 preset_prompts 行，迁移应正常完成
      final legacyDb = createLegacyV8Db();
      legacyDb.close();

      final migrated = AppDatabase.forPath(dbPath);
      addTearDown(migrated.close);

      final version = migrated.connection
          .select('PRAGMA user_version;')
          .single['user_version'] as int;
      expect(version, greaterThanOrEqualTo(10));

      final columns = migrated.connection
          .select('PRAGMA table_info(preset_prompts);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, isNot(contains('system_prompt')));
    });
  });

  group('V10 迁移', () {
    test('迁移后 favorites 表包含 title 列', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final columns = db.connection.select('PRAGMA table_info(favorites);');
      final columnNames = columns.map((row) => row['name'] as String).toList();

      expect(columnNames, contains('title'));
    });

    test('迁移后 user_version >= 10', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final version =
          db.connection.select('PRAGMA user_version;').single['user_version']
              as int;
      expect(version, greaterThanOrEqualTo(10));
    });

    test('全新安装 favorites 表含 title 列且默认为 NULL', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      db.connection.execute(
        "INSERT INTO favorites (id, user_message_content, assistant_content, created_at) "
        "VALUES ('fav-1', 'hello', 'world', '2025-01-01T00:00:00.000');",
      );

      final rows = db.connection.select('SELECT title FROM favorites WHERE id = ?;', ['fav-1']);
      expect(rows.length, 1);
      expect(rows.first['title'], isNull);
    });

    test('从 v9 升级时 ALTER TABLE 添加 title 列且已有数据保留', () {
      final tempDir = Directory.systemTemp.createTempSync('v9-migration-test-');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final dbPath = '${tempDir.path}${Platform.pathSeparator}test_v9.db';

      // 构造一个 v9 数据库：favorites 表无 title 列
      final legacyDb = sqlite.sqlite3.open(dbPath);
      legacyDb.execute('PRAGMA foreign_keys = ON;');
      legacyDb.execute('''
        CREATE TABLE favorites (
          id TEXT PRIMARY KEY,
          collection_id TEXT,
          user_message_content TEXT NOT NULL,
          assistant_content TEXT NOT NULL,
          assistant_reasoning_content TEXT NOT NULL DEFAULT '',
          source_conversation_id TEXT,
          source_conversation_title TEXT,
          created_at TEXT NOT NULL,
          assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型'
        );
      ''');
      legacyDb.execute(
        "INSERT INTO favorites (id, user_message_content, assistant_content, created_at) "
        "VALUES ('fav-old', '旧消息', '旧回复', '2025-01-01T00:00:00.000');",
      );
      legacyDb.execute('PRAGMA user_version = 9;');
      legacyDb.close();

      // 重新打开触发 _migrateV10 的 ALTER TABLE 路径
      final migrated = AppDatabase.forPath(dbPath);
      addTearDown(migrated.close);

      // user_version 升到 10
      final version = migrated.connection
          .select('PRAGMA user_version;')
          .single['user_version'] as int;
      expect(version, greaterThanOrEqualTo(10));

      // favorites 表包含 title 列
      final columns = migrated.connection
          .select('PRAGMA table_info(favorites);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, contains('title'));

      // 旧数据保留，title 默认为 NULL
      final rows = migrated.connection.select('SELECT id, title FROM favorites WHERE id = ?;', ['fav-old']);
      expect(rows.length, 1);
      expect(rows.first['title'], isNull);
    });
  });

  group('V13 迁移', () {
    test('迁移后 messages 表包含 finish_reason 列', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final columns = db.connection.select('PRAGMA table_info(messages);');
      final columnNames = columns.map((row) => row['name'] as String).toList();

      expect(columnNames, contains('finish_reason'));
    });

    test('迁移后 user_version >= 13', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final version =
          db.connection.select('PRAGMA user_version;').single['user_version']
              as int;
      expect(version, greaterThanOrEqualTo(13));
    });

    test('全新安装 messages 表含 finish_reason 列且默认为 NULL', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      db.connection.execute(
        "INSERT INTO conversations (id, created_at, updated_at, reasoning_effort) "
        "VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');",
      );
      db.connection.execute(
        "INSERT INTO messages (id, conversation_id, node_index, role, content, created_at) "
        "VALUES ('m1', 'c1', 0, 'user', 'hello', '2026-01-01');",
      );

      final rows = db.connection.select('SELECT finish_reason FROM messages WHERE id = ?;', ['m1']);
      expect(rows.length, 1);
      expect(rows.first['finish_reason'], isNull);
    });

    test('从 v12 升级时 ALTER TABLE 添加 finish_reason 列且已有数据保留', () {
      final tempDir = Directory.systemTemp.createTempSync('v12-migration-test-');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final dbPath = '${tempDir.path}${Platform.pathSeparator}test_v12.db';

      // 构造一个 v12 数据库：messages 表无 finish_reason 列（含 V12 新增的模板列）
      final legacyDb = sqlite.sqlite3.open(dbPath);
      legacyDb.execute('PRAGMA foreign_keys = ON;');
      legacyDb.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          title TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          selected_model_id TEXT,
          selected_preset_prompt_id TEXT,
          reasoning_enabled INTEGER NOT NULL DEFAULT 0,
          reasoning_effort TEXT NOT NULL,
          selected_checkpoint_id TEXT,
          excluded_message_ids_json TEXT NOT NULL DEFAULT '[]',
          auto_retry_enabled INTEGER NOT NULL DEFAULT 0
        );
      ''');
      legacyDb.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          node_index INTEGER NOT NULL,
          parent_id TEXT,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          reasoning_content TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
          user_message_segments_json TEXT NOT NULL DEFAULT '[]',
          applied_checkpoint_title TEXT NOT NULL DEFAULT '',
          template_prompt_id TEXT DEFAULT NULL,
          template_variable_values_json TEXT NOT NULL DEFAULT '{}',
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        );
      ''');
      legacyDb.execute(
        "INSERT INTO conversations (id, created_at, updated_at, reasoning_effort) "
        "VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');",
      );
      legacyDb.execute(
        "INSERT INTO messages (id, conversation_id, node_index, role, content, created_at) "
        "VALUES ('m-old', 'c1', 0, 'user', '旧消息内容', '2026-01-01');",
      );
      legacyDb.execute('PRAGMA user_version = 12;');
      legacyDb.close();

      // 重新打开触发 _migrateV13 的 ALTER TABLE 路径
      final migrated = AppDatabase.forPath(dbPath);
      addTearDown(migrated.close);

      // user_version 升到 >= 13
      final version = migrated.connection
          .select('PRAGMA user_version;')
          .single['user_version'] as int;
      expect(version, greaterThanOrEqualTo(13));

      // messages 表包含 finish_reason 列
      final columns = migrated.connection
          .select('PRAGMA table_info(messages);')
          .map((row) => row['name'] as String)
          .toList();
      expect(columns, contains('finish_reason'));

      // 旧数据保留，content 不变，finish_reason 默认为 NULL
      final rows = migrated.connection.select('SELECT id, content, finish_reason FROM messages WHERE id = ?;', ['m-old']);
      expect(rows.length, 1);
      expect(rows.first['content'], equals('旧消息内容'));
      expect(rows.first['finish_reason'], isNull);
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
