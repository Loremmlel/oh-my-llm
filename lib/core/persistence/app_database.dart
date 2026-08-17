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
    try {
      _configure();
      _initializeSchema();
    } catch (_) {
      // schema 初始化失败（如版本不匹配被拒绝）时释放连接，避免文件句柄泄漏。
      _connection.close();
      rethrow;
    }
  }

  /// 当前滚动迁移基线：全新数据库直接创建到该版本。
  ///
  /// 历史 V9→V13 逐级迁移已退役，低于或高于该版本的数据库都会被显式拒绝打开。
  static const int currentSchemaVersion = 13;

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
    return AppDatabase._(connection: sqlite.sqlite3.open(path), path: path);
  }

  sqlite.Database get connection => _connection;

  /// 关闭数据库连接。
  void close() {
    _connection.close();
  }

  void _configure() {
    configureSqlitePragmas(_connection, isInMemory: path == ':memory:');
  }

  /// 校验 schema 版本与当前滚动基线是否一致，并在全新库上直接建当前 schema。
  ///
  /// - `user_version == 0`：全新数据库，创建完整当前 schema 后标记为
  ///   [currentSchemaVersion]；
  /// - `user_version == [currentSchemaVersion]`：当前版本数据库，不做任何改动；
  /// - `0 < user_version < [currentSchemaVersion]`：旧版应用遗留的数据库，
  ///   显式拒绝，避免仓库层在旧 schema 上执行当前查询造成误读误写；
  /// - `user_version > [currentSchemaVersion]`：更新版本应用创建的数据库，
  ///   同样显式拒绝，避免旧代码静默读写新表结构。
  void _initializeSchema() {
    final currentVersion =
        _connection.select('PRAGMA user_version;').single['user_version']
            as int;
    if (currentVersion == 0) {
      _createSchema();
      _connection.execute('PRAGMA user_version = $currentSchemaVersion;');
    } else if (currentVersion != currentSchemaVersion) {
      throw AppDatabaseSchemaVersionException(currentVersion);
    }
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
        template_prompt_id TEXT DEFAULT NULL,
        template_variable_values_json TEXT NOT NULL DEFAULT '{}',
        finish_reason TEXT DEFAULT NULL,
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
        source_assistant_message_id TEXT,
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

/// 数据库 schema 版本与当前滚动基线不匹配时抛出。
///
/// 低于 [AppDatabase.currentSchemaVersion] 说明是旧版应用遗留的数据库，
/// 高于则说明由更新版本的应用创建；两者都无法在当前代码下安全读写。
class AppDatabaseSchemaVersionException implements Exception {
  AppDatabaseSchemaVersionException(this.version);

  /// 数据库实际报告的 user_version。
  final int version;

  @override
  String toString() {
    if (version < AppDatabase.currentSchemaVersion) {
      return '不支持的旧版数据库 schema（user_version=$version < '
          '${AppDatabase.currentSchemaVersion}）：已超出自动升级范围，'
          '请使用当前版本重建或迁移数据';
    }
    return '数据库 schema 由更新版本的应用创建（user_version=$version > '
        '${AppDatabase.currentSchemaVersion}）：当前版本拒绝打开以避免损坏数据';
  }
}
