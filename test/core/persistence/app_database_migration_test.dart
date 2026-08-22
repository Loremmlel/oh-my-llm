import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
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

    test('全新数据库创建后立即播种系统未分类收藏夹', () {
      final rows = database.connection.select(
        'SELECT id, name FROM collections WHERE id = ?;',
        [AppReservedEntities.uncategorizedFavoriteCollectionId],
      );
      expect(rows, hasLength(1));
      expect(
        rows.single['name'],
        AppReservedEntities.uncategorizedFavoriteCollectionName,
      );
    });

    test('favorites 归属列必填且外键动作为 RESTRICT', () {
      final columns = {
        for (final row in database.connection.select(
          'PRAGMA table_info(favorites);',
        ))
          row['name'] as String: row,
      };
      expect(columns['collection_id']!['notnull'] as int, 1);
      expect(columns['collection_assigned_at']!['notnull'] as int, 1);

      final onDeleteActions = database.connection
          .select('PRAGMA foreign_key_list(favorites);')
          .map((row) => row['on_delete'] as String)
          .toList();
      expect(onDeleteActions, everyElement('RESTRICT'));
    });

    test('收藏分页与卡片聚合索引存在且列序正确', () {
      final indexColumns = <String, List<String>>{
        for (final indexName in [
          'idx_favorites_collection_created',
          'idx_favorites_collection_assigned',
        ])
          indexName: database.connection
              .select('PRAGMA index_info($indexName);')
              .map((row) => row['name'] as String)
              .toList(),
      };
      expect(indexColumns['idx_favorites_collection_created'], [
        'collection_id',
        'created_at',
        'id',
      ]);
      expect(indexColumns['idx_favorites_collection_assigned'], [
        'collection_id',
        'collection_assigned_at',
      ]);
    });

    test('favorites.title 列默认为 NULL', () {
      database.connection.execute(
        "INSERT INTO favorites (id, collection_id, collection_assigned_at, "
        "user_message_content, assistant_content, created_at) "
        "VALUES ('fav-1', '${AppReservedEntities.uncategorizedFavoriteCollectionId}', "
        "'2025-01-01T00:00:00.000', 'hello', 'world', '2025-01-01T00:00:00.000');",
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

    test('外键 RESTRICT 拒绝删除仍有收藏的收藏夹，收藏移走后可删除', () {
      database.connection.execute('''
        INSERT INTO collections (id, name, created_at)
        VALUES ('col-1', '测试收藏夹', '2026-01-01');
      ''');
      database.connection.execute('''
        INSERT INTO favorites (
          id, collection_id, collection_assigned_at,
          user_message_content, assistant_content, created_at
        ) VALUES ('f1', 'col-1', '2026-01-01', '问题', '回答', '2026-01-01');
      ''');

      // v14 起删除收藏夹不再静默置空归属，而是被外键直接拒绝。
      expect(
        () => database.connection.execute(
          "DELETE FROM collections WHERE id = 'col-1';",
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        database.connection
            .select("SELECT COUNT(*) AS c FROM collections WHERE id = 'col-1';")
            .single['c'],
        1,
      );

      database.connection.execute("DELETE FROM favorites WHERE id = 'f1';");
      database.connection.execute(
        "DELETE FROM collections WHERE id = 'col-1';",
      );
      expect(
        database.connection.select(
          "SELECT * FROM collections WHERE id = 'col-1';",
        ),
        isEmpty,
      );
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
      final dbPath = '${tempDir.path}${Platform.pathSeparator}test_current.db';

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
        // 打开即抛异常：连接不会交给任何仓库层在旧 schema 上执行查询，
        // 且异常携带实际 user_version，供上层识别被拒绝的具体原因。
        expect(
          () => AppDatabase.forPath(path),
          throwsA(
            isA<AppDatabaseSchemaVersionException>().having(
              (exception) => exception.version,
              'version',
              version,
            ),
          ),
        );
      }
    });

    test('高于当前基线的未来版本数据库显式拒绝打开', () {
      final path = createDbFile('future_15.db', 15);
      // 旧代码不静默读写更新版本应用创建的 schema；异常携带实际 user_version。
      expect(
        () => AppDatabase.forPath(path),
        throwsA(
          isA<AppDatabaseSchemaVersionException>().having(
            (exception) => exception.version,
            'version',
            15,
          ),
        ),
      );
    });
  });

  group('AppDatabase v13→v14 收藏迁移', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'appdb-favorites-v14-test-',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// 构造一份真实的 v13 文件数据库。
    ///
    /// 只建迁移涉及的 collections/favorites 两张表与旧索引；
    /// 其余业务表与该迁移逻辑无关。
    String createV13Database(String name) {
      final path = '${tempDir.path}${Platform.pathSeparator}$name';
      final db = sqlite.sqlite3.open(path);
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('''
        CREATE TABLE collections (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      ''');
      db.execute('''
        CREATE TABLE favorites (
          id TEXT PRIMARY KEY,
          collection_id TEXT,
          user_message_content TEXT NOT NULL,
          assistant_content TEXT NOT NULL,
          assistant_reasoning_content TEXT NOT NULL DEFAULT '',
          source_conversation_id TEXT,
          source_conversation_title TEXT,
          source_assistant_message_id TEXT,
          created_at TEXT NOT NULL,
          assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
          title TEXT,
          FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE SET NULL
        );
      ''');
      db.execute(
        'CREATE INDEX idx_favorites_created_at ON favorites(created_at DESC);',
      );
      db.execute('PRAGMA user_version = 13;');
      db.close();
      return path;
    }

    /// 以 raw SQL 向 v13 库写入一条收藏记录。
    void insertV13Favorite(
      String path, {
      required String id,
      String? collectionId,
      String userMessageContent = '默认问题',
      String assistantContent = '默认回答',
      String reasoningContent = '',
      String? sourceConversationId,
      String? sourceConversationTitle,
      String? sourceAssistantMessageId,
      String createdAt = '2026-03-01T10:00:00.000',
      String modelDisplayName = '匿名模型',
      String? title,
    }) {
      final db = sqlite.sqlite3.open(path);
      // 孤儿/空串归属是旧版本在约束关闭期留下的脏数据，只能绕过外键造出。
      db.execute('PRAGMA foreign_keys = OFF;');
      db.execute(
        'INSERT INTO favorites ('
        'id, collection_id, user_message_content, assistant_content, '
        'assistant_reasoning_content, source_conversation_id, '
        'source_conversation_title, source_assistant_message_id, created_at, '
        'assistant_model_display_name, title) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          id,
          collectionId,
          userMessageContent,
          assistantContent,
          reasoningContent,
          sourceConversationId,
          sourceConversationTitle,
          sourceAssistantMessageId,
          createdAt,
          modelDisplayName,
          title,
        ],
      );
      db.close();
    }

    /// 以 raw SQL 向 v13 库写入一个收藏夹。
    void insertV13Collection(
      String path, {
      required String id,
      required String name,
      String createdAt = '2026-02-01T09:00:00.000',
    }) {
      final db = sqlite.sqlite3.open(path);
      db.execute(
        'INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?);',
        [id, name, createdAt],
      );
      db.close();
    }

    test('未归属、空归属与孤儿收藏迁移进系统收藏夹且归属时间取收藏时间', () {
      final path = createV13Database('migrate_unassigned.db');
      insertV13Favorite(
        path,
        id: 'fav-null',
        createdAt: '2026-03-01T10:00:00.000',
      );
      insertV13Favorite(
        path,
        id: 'fav-empty',
        collectionId: '',
        createdAt: '2026-03-02T10:00:00.000',
      );
      insertV13Favorite(
        path,
        id: 'fav-orphan',
        collectionId: 'ghost-collection',
        createdAt: '2026-03-03T10:00:00.000',
      );

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      for (final id in ['fav-null', 'fav-empty', 'fav-orphan']) {
        final row = database.connection.select(
          'SELECT collection_id, collection_assigned_at, created_at '
          'FROM favorites WHERE id = ?;',
          [id],
        ).single;
        expect(
          row['collection_id'],
          AppReservedEntities.uncategorizedFavoriteCollectionId,
          reason: id,
        );
        expect(row['collection_assigned_at'], row['created_at'], reason: id);
      }
    });

    test('普通收藏夹内的收藏保持原归属不变', () {
      final path = createV13Database('migrate_normal.db');
      insertV13Collection(path, id: 'col-a', name: '技术笔记');
      insertV13Favorite(
        path,
        id: 'fav-a',
        collectionId: 'col-a',
        createdAt: '2026-03-01T10:00:00.000',
      );

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      final row = database.connection
          .select(
            "SELECT collection_id, collection_assigned_at FROM favorites WHERE id = 'fav-a';",
          )
          .single;
      expect(row['collection_id'], 'col-a');
      expect(row['collection_assigned_at'], '2026-03-01T10:00:00.000');
    });

    test('迁移逐列保留收藏的全部内容字段', () {
      final path = createV13Database('migrate_columns.db');
      insertV13Favorite(
        path,
        id: 'fav-full',
        userMessageContent: '解释一下闭包',
        assistantContent: '闭包是函数与其词法环境的组合……',
        reasoningContent: '先回忆闭包的定义再举例',
        sourceConversationId: 'conv-9',
        sourceConversationTitle: 'Dart 学习',
        sourceAssistantMessageId: 'msg-42',
        createdAt: '2026-03-05T08:30:00.000',
        modelDisplayName: 'DeepSeek V4 Flash',
        title: '闭包笔记',
      );

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      final row = database.connection
          .select("SELECT * FROM favorites WHERE id = 'fav-full';")
          .single;
      expect(row['user_message_content'], '解释一下闭包');
      expect(row['assistant_content'], '闭包是函数与其词法环境的组合……');
      expect(row['assistant_reasoning_content'], '先回忆闭包的定义再举例');
      expect(row['source_conversation_id'], 'conv-9');
      expect(row['source_conversation_title'], 'Dart 学习');
      expect(row['source_assistant_message_id'], 'msg-42');
      expect(row['created_at'], '2026-03-05T08:30:00.000');
      expect(row['assistant_model_display_name'], 'DeepSeek V4 Flash');
      expect(row['title'], '闭包笔记');
    });

    test('v13 无收藏夹时迁移仍播种唯一的系统收藏夹', () {
      final path = createV13Database('migrate_no_collections.db');
      insertV13Favorite(path, id: 'fav-1');

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      final rows = database.connection.select('SELECT id FROM collections;');
      expect(rows, hasLength(1));
      expect(
        rows.single['id'],
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(
        database.connection
            .select("SELECT collection_id FROM favorites WHERE id = 'fav-1';")
            .single['collection_id'],
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
    });

    test('迁移后系统收藏夹恰好一条，且不复用名为未分类的普通收藏夹', () {
      final path = createV13Database('migrate_system_row.db');
      insertV13Collection(path, id: 'col-legacy-name', name: '未分类');

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      final systemRows = database.connection.select(
        'SELECT id, name FROM collections WHERE id = ?;',
        [AppReservedEntities.uncategorizedFavoriteCollectionId],
      );
      expect(systemRows, hasLength(1));
      expect(
        systemRows.single['name'],
        AppReservedEntities.uncategorizedFavoriteCollectionName,
      );

      // 同名普通行保留原 ID，不会被升级为系统行。
      final legacyRow = database.connection
          .select("SELECT name FROM collections WHERE id = 'col-legacy-name';")
          .single;
      expect(legacyRow['name'], '未分类');
    });

    test('迁移完成的数据库重新打开时保持幂等', () {
      final path = createV13Database('migrate_reopen.db');
      insertV13Collection(path, id: 'col-a', name: '技术笔记');
      insertV13Favorite(path, id: 'fav-null');
      insertV13Favorite(
        path,
        id: 'fav-a',
        collectionId: 'col-a',
        createdAt: '2026-03-02T10:00:00.000',
      );

      final first = AppDatabase.forPath(path);
      expect(
        first.connection.select('PRAGMA user_version;').single['user_version']
            as int,
        greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
      );
      final firstFavorites = first.connection.select(
        'SELECT id, collection_id FROM favorites ORDER BY id;',
      );
      final firstCollections = first.connection.select(
        'SELECT id FROM collections ORDER BY id;',
      );
      first.close();

      final second = AppDatabase.forPath(path);
      addTearDown(second.close);
      expect(
        second.connection.select(
          'SELECT id, collection_id FROM favorites ORDER BY id;',
        ),
        firstFavorites,
      );
      expect(
        second.connection.select('SELECT id FROM collections ORDER BY id;'),
        firstCollections,
      );
    });

    test('外键约束拒绝删除仍有收藏的系统收藏夹与普通收藏夹', () {
      final path = createV13Database('migrate_restrict.db');
      insertV13Collection(path, id: 'col-a', name: '技术笔记');
      insertV13Favorite(path, id: 'fav-sys');
      insertV13Favorite(
        path,
        id: 'fav-a',
        collectionId: 'col-a',
        createdAt: '2026-03-02T10:00:00.000',
      );

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      expect(
        () => database.connection.execute(
          'DELETE FROM collections WHERE id = ?;',
          [AppReservedEntities.uncategorizedFavoriteCollectionId],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        () => database.connection.execute(
          "DELETE FROM collections WHERE id = 'col-a';",
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      // 被拒后两个收藏夹都仍在。
      expect(
        database.connection
            .select('SELECT COUNT(*) AS c FROM collections;')
            .single['c'],
        2,
      );
    });

    test('favorites 缺失 title 列的 v13 库迁移时自动补列且数据完整', () {
      final path = createV13Database('migrate_missing_title.db');
      insertV13Collection(path, id: 'col-a', name: '技术笔记');
      insertV13Favorite(
        path,
        id: 'fav-titled',
        collectionId: 'col-a',
        title: '会被丢弃的旧标题',
        createdAt: '2026-03-01T10:00:00.000',
      );
      insertV13Favorite(
        path,
        id: 'fav-untitled',
        createdAt: '2026-03-02T10:00:00.000',
      );

      // 真实用户库形态：未合入 master 的历史构建把 user_version 写成 13，
      // 但 favorites 缺少 V10 引入的 title 列。这里删列复现该形态，
      // 验证迁移对这种"版本号与结构脱节"的库自愈而非在 prepare 阶段崩溃。
      final legacy = sqlite.sqlite3.open(path);
      legacy.execute('ALTER TABLE favorites DROP COLUMN title;');
      legacy.close();

      final database = AppDatabase.forPath(path);
      addTearDown(database.close);

      expect(
        database.connection
                .select('PRAGMA user_version;')
                .single['user_version']
            as int,
        greaterThanOrEqualTo(AppDatabase.currentSchemaVersion),
      );
      final titled = database.connection
          .select(
            "SELECT collection_id, title, collection_assigned_at "
            "FROM favorites WHERE id = 'fav-titled';",
          )
          .single;
      expect(titled['collection_id'], 'col-a');
      expect(titled['title'], isNull);
      expect(titled['collection_assigned_at'], '2026-03-01T10:00:00.000');

      final untitled = database.connection
          .select(
            "SELECT collection_id, title, collection_assigned_at, created_at "
            "FROM favorites WHERE id = 'fav-untitled';",
          )
          .single;
      expect(
        untitled['collection_id'],
        AppReservedEntities.uncategorizedFavoriteCollectionId,
      );
      expect(untitled['title'], isNull);
      expect(untitled['collection_assigned_at'], untitled['created_at']);
    });

    test('迁移中途失败时回滚且原始 v13 数据完好', () {
      final path = createV13Database('migrate_rollback.db');
      insertV13Collection(path, id: 'col-a', name: '技术笔记');
      insertV13Favorite(
        path,
        id: 'fav-1',
        collectionId: 'col-a',
        createdAt: '2026-03-01T10:00:00.000',
      );

      // 预占用迁移重建 favorites 时使用的中间表名，迫使迁移在事务中途失败。
      final blocker = sqlite.sqlite3.open(path);
      blocker.execute('CREATE TABLE favorites_v14 (id TEXT PRIMARY KEY);');
      blocker.close();

      expect(
        () => AppDatabase.forPath(path),
        throwsA(isA<sqlite.SqliteException>()),
      );

      // 原始 v13 数据仍可由 raw sqlite 读取：版本未推进、系统夹未写入、
      // 原归属未被改动。
      final raw = sqlite.sqlite3.open(path);
      addTearDown(raw.close);
      expect(raw.select('PRAGMA user_version;').single['user_version'], 13);
      expect(raw.select('SELECT COUNT(*) AS c FROM favorites;').single['c'], 1);
      expect(
        raw.select('SELECT COUNT(*) AS c FROM collections WHERE id = ?;', [
          AppReservedEntities.uncategorizedFavoriteCollectionId,
        ]).single['c'],
        0,
      );
      expect(
        raw
            .select("SELECT collection_id FROM favorites WHERE id = 'fav-1';")
            .single['collection_id'],
        'col-a',
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
