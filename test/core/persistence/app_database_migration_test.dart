import 'package:flutter_test/flutter_test.dart';

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

    // ── user_version ───────────────────────────────────────────────────────

    test('user_version 在迁移完成后为 4', () {
      final version =
          database.connection
                  .select('PRAGMA user_version;')
                  .single['user_version']
              as int;
      expect(version, 4);
    });

    // ── V1 表结构 ──────────────────────────────────────────────────────────

    test('V1 创建 conversations 表并包含所有列', () {
      final columns = _columnNames(database, 'conversations');
      expect(
        columns,
        containsAll([
          'id',
          'title',
          'created_at',
          'updated_at',
          'selected_model_id',
          'selected_prompt_template_id',
          'reasoning_enabled',
          'reasoning_effort',
        ]),
      );
    });

    test('V1 创建 messages 表并包含所有列', () {
      final columns = _columnNames(database, 'messages');
      expect(
        columns,
        containsAll([
          'id',
          'conversation_id',
          'node_index',
          'parent_id',
          'role',
          'content',
          'reasoning_content',
          'assistant_model_display_name',
          'created_at',
        ]),
      );
    });

    test('V1 创建 conversation_branch_selections 表', () {
      final tables = _tableNames(database);
      expect(tables, contains('conversation_branch_selections'));
    });

    test('V1 messages.reasoning_content 默认值为空字符串', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'user', 'hello', '2026-01-01');
      ''');
      final row = database.connection
          .select("SELECT reasoning_content FROM messages WHERE id = 'm1';")
          .single;
      expect(row['reasoning_content'], '');
    });

    // ── V1 外键级联 ────────────────────────────────────────────────────────

    test('删除 conversation 后级联删除 messages', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'user', 'hello', '2026-01-01');
      ''');
      database.connection.execute("DELETE FROM conversations WHERE id = 'c1';");

      final messages = database.connection.select(
        "SELECT * FROM messages WHERE conversation_id = 'c1';",
      );
      expect(messages, isEmpty);
    });

    test('删除 conversation 后级联删除 conversation_branch_selections', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO conversation_branch_selections (conversation_id, parent_id, child_id)
        VALUES ('c1', 'root', 'm1');
      ''');
      database.connection.execute("DELETE FROM conversations WHERE id = 'c1';");

      final selections = database.connection.select(
        "SELECT * FROM conversation_branch_selections WHERE conversation_id = 'c1';",
      );
      expect(selections, isEmpty);
    });

    // ── V2 表结构 ──────────────────────────────────────────────────────────

    test('V2 创建 prompt_templates 表', () {
      final tables = _tableNames(database);
      expect(tables, contains('prompt_templates'));
    });

    test('V2 创建 fixed_prompt_sequences 表', () {
      final tables = _tableNames(database);
      expect(tables, contains('fixed_prompt_sequences'));
    });

    test('V2 prompt_templates.messages_json 默认值为空数组字符串', () {
      database.connection.execute('''
        INSERT INTO prompt_templates (id, name, updated_at)
        VALUES ('tpl-1', '测试模板', '2026-01-01');
      ''');
      final row = database.connection
          .select(
            "SELECT messages_json FROM prompt_templates WHERE id = 'tpl-1';",
          )
          .single;
      expect(row['messages_json'], '[]');
    });

    // ── V3 表结构 ──────────────────────────────────────────────────────────

    test('V3 创建 collections 表', () {
      final tables = _tableNames(database);
      expect(tables, contains('collections'));
    });

    test('V3 创建 favorites 表', () {
      final tables = _tableNames(database);
      expect(tables, contains('favorites'));
    });

    test('V3 favorites 包含所有列', () {
      final columns = _columnNames(database, 'favorites');
      expect(
        columns,
        containsAll([
          'id',
          'collection_id',
          'user_message_content',
          'assistant_content',
          'assistant_reasoning_content',
          'assistant_model_display_name',
          'source_conversation_id',
          'source_conversation_title',
          'created_at',
        ]),
      );
    });

    test('V3 favorites.assistant_reasoning_content 默认值为空字符串', () {
      database.connection.execute('''
        INSERT INTO favorites (
          id, user_message_content, assistant_content, created_at
        ) VALUES ('f1', '问题', '回答', '2026-01-01');
      ''');
      final row = database.connection
          .select(
            "SELECT assistant_reasoning_content FROM favorites WHERE id = 'f1';",
          )
          .single;
      expect(row['assistant_reasoning_content'], '');
    });

    test('V4 messages.assistant_model_display_name 默认值为匿名模型', () {
      database.connection.execute('''
        INSERT INTO conversations (id, created_at, updated_at, reasoning_effort)
        VALUES ('c1', '2026-01-01', '2026-01-01', 'medium');
      ''');
      database.connection.execute('''
        INSERT INTO messages (id, conversation_id, node_index, role, content, created_at)
        VALUES ('m1', 'c1', 0, 'assistant', 'hello', '2026-01-01');
      ''');
      final row = database.connection
          .select(
            "SELECT assistant_model_display_name FROM messages WHERE id = 'm1';",
          )
          .single;
      expect(row['assistant_model_display_name'], '匿名模型');
    });

    test('V4 favorites.assistant_model_display_name 默认值为匿名模型', () {
      database.connection.execute('''
        INSERT INTO favorites (
          id, user_message_content, assistant_content, created_at
        ) VALUES ('f1', '问题', '回答', '2026-01-01');
      ''');
      final row = database.connection
          .select(
            "SELECT assistant_model_display_name FROM favorites WHERE id = 'f1';",
          )
          .single;
      expect(row['assistant_model_display_name'], '匿名模型');
    });

    // ── V3 外键 ON DELETE SET NULL ─────────────────────────────────────────

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

    // ── 索引 ───────────────────────────────────────────────────────────────

    test('conversations 表存在 updated_at 降序索引', () {
      final indexes = _indexNames(database, 'conversations');
      expect(indexes, contains('idx_conversations_updated_at'));
    });

    test('favorites 表存在 created_at 和 collection_id 索引', () {
      final indexes = _indexNames(database, 'favorites');
      expect(
        indexes,
        containsAll([
          'idx_favorites_created_at',
          'idx_favorites_collection_id',
        ]),
      );
    });
  });
}

/// 返回指定表的所有列名。
List<String> _columnNames(AppDatabase database, String tableName) {
  return database.connection
      .select("PRAGMA table_info($tableName);")
      .map((row) => row['name'] as String)
      .toList();
}

/// 返回数据库中所有用户创建的表名。
List<String> _tableNames(AppDatabase database) {
  return database.connection
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      )
      .map((row) => row['name'] as String)
      .toList();
}

/// 返回指定表上的所有索引名。
List<String> _indexNames(AppDatabase database, String tableName) {
  return database.connection
      .select("PRAGMA index_list($tableName);")
      .map((row) => row['name'] as String)
      .toList();
}
