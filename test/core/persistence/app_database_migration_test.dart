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

    test('user_version 在迁移完成后为 9', () {
      final version =
          database.connection
                  .select('PRAGMA user_version;')
                  .single['user_version']
              as int;
      expect(version, greaterThanOrEqualTo(9));
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
}

List<String> _tableNames(AppDatabase database) {
  return database.connection
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
      )
      .map((row) => row['name'] as String)
      .toList();
}
