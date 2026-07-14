import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'sqlite_replace_all.dart';

const chatDatabaseFileName = 'chat_history.sqlite';

/// 应用级 SQLite 数据库，负责打开文件并维护基础 schema。
class AppDatabase {
  AppDatabase._({required sqlite.Database connection, required this.path})
    : _connection = connection {
    _configure();
    _migrate();
  }

  final sqlite.Database _connection;
  final String path;

  /// 打开正式数据库文件，并在首次使用时创建 schema。
  static Future<AppDatabase> open() async {
    final supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);
    final databasePath =
        '${supportDirectory.path}${Platform.pathSeparator}$chatDatabaseFileName';
    return AppDatabase._(
      connection: sqlite.sqlite3.open(databasePath),
      path: databasePath,
    );
  }

  /// 打开测试用内存数据库。
  factory AppDatabase.inMemory() {
    return AppDatabase._(
      connection: sqlite.sqlite3.openInMemory(),
      path: ':memory:',
    );
  }

  /// 打开指定路径的文件数据库，用于需要跨 Isolate 共享的测试场景。
  @visibleForTesting
  factory AppDatabase.forPath(String path) {
    return AppDatabase._(
      connection: sqlite.sqlite3.open(path),
      path: path,
    );
  }

  sqlite.Database get connection => _connection;

  /// 关闭数据库连接。
  void close() {
    _connection.close();
  }

  void _configure() {
    configureSqlitePragmas(_connection, isInMemory: path == ':memory:');
  }

  void _migrate() {
    final currentVersion =
        _connection.select('PRAGMA user_version;').single['user_version']
            as int;
    if (currentVersion < 9) {
      _migrateV9(currentVersion);
    }
    if (currentVersion < 10) {
      _migrateV10(currentVersion);
    }
  }

  /// V9：移除 preset_prompts.system_prompt 列。
  ///
  /// 全新安装直接建表；已有数据库先合并旧 system_prompt 数据再删列。
  void _migrateV9(int fromVersion) {
    if (fromVersion == 0) {
      _createSchema();
    } else {
      _mergeLegacySystemPrompts();
      _connection.execute(
        'ALTER TABLE preset_prompts DROP COLUMN system_prompt;',
      );
    }
    _connection.execute('PRAGMA user_version = 9;');
  }

  /// 将 preset_prompts 中非空的 system_prompt 合并到 messages_json 头部。
  void _mergeLegacySystemPrompts() {
    final rows = _connection.select('''
      SELECT id, system_prompt, messages_json
      FROM preset_prompts
      WHERE system_prompt != '' AND system_prompt IS NOT NULL;
    ''');

    for (final row in rows) {
      final messagesJson = row['messages_json'] as String;
      final messages = jsonDecode(messagesJson) as List;
      final hasSystem = messages.any(
        (item) => item is Map && item['role'] == 'system',
      );
      if (hasSystem) continue;

      final systemMessage = {
        'id': '_legacy-system-message',
        'role': 'system',
        'title': 'system',
        'content': row['system_prompt'] as String,
        'placement': 'before',
        'enabled': true,
      };
      final updated = [systemMessage, ...messages];
      final id = row['id'] as String;
      _connection.execute(
        'UPDATE preset_prompts SET messages_json = ? WHERE id = ?;',
        [jsonEncode(updated), id],
      );
    }
  }

  /// V10：favorites 表新增 title 列，用于自定义收藏标题。
  void _migrateV10(int fromVersion) {
    if (fromVersion == 0) {
      // 全新安装，_createSchema 已包含 title 列
    } else {
      // 旧版数据库可能没有 favorites 表（如 v8 测试库），先确保表存在
      final hasFavorites = _connection
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'favorites';",
          )
          .isNotEmpty;
      if (hasFavorites) {
        _connection.execute(
          'ALTER TABLE favorites ADD COLUMN title TEXT;',
        );
      }
    }
    _connection.execute('PRAGMA user_version = 10;');
  }

  /// 创建全部业务表和索引（全新安装时使用）。
  void _createSchema() {
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
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
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS messages (
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
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS conversation_branch_selections (
        conversation_id TEXT NOT NULL,
        parent_id TEXT NOT NULL,
        child_id TEXT NOT NULL,
        PRIMARY KEY (conversation_id, parent_id),
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_conversations_updated_at
      ON conversations(updated_at DESC);
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_node_index
      ON messages(conversation_id, node_index);
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_parent
      ON messages(conversation_id, parent_id);
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS preset_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        messages_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS fixed_prompt_sequences (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        steps_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        id TEXT PRIMARY KEY,
        collection_id TEXT,
        user_message_content TEXT NOT NULL,
        assistant_content TEXT NOT NULL,
        assistant_reasoning_content TEXT NOT NULL DEFAULT '',
        source_conversation_id TEXT,
        source_conversation_title TEXT,
        created_at TEXT NOT NULL,
        assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
        title TEXT,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE SET NULL
      );
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorites_created_at
      ON favorites(created_at DESC);
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorites_collection_id
      ON favorites(collection_id);
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS template_prompts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        variables_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS memory_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS conversation_checkpoints (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        parent_checkpoint_id TEXT,
        covered_until_message_id TEXT,
        source_memory_prompt_name TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_conversation_checkpoints_conversation_created_at
      ON conversation_checkpoints(conversation_id, created_at DESC);
    ''');
  }
}
