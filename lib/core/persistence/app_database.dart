import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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

  sqlite.Database get connection => _connection;

  /// 关闭数据库连接。
  void close() {
    _connection.dispose();
  }

  void _configure() {
    _connection.execute('PRAGMA foreign_keys = ON;');
    if (path != ':memory:') {
      _connection.execute('PRAGMA journal_mode = WAL;');
    }
  }

  void _migrate() {
    final currentVersion =
        _connection.select('PRAGMA user_version;').single['user_version']
            as int;

    if (currentVersion < 1) {
      _migrateV1();
    }
    if (currentVersion < 2) {
      _migrateV2();
    }
    if (currentVersion < 3) {
      _migrateV3();
    }
  }

  /// 初始 schema：聊天记录相关表。
  void _migrateV1() {
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        selected_model_id TEXT,
        selected_prompt_template_id TEXT,
        reasoning_enabled INTEGER NOT NULL DEFAULT 0,
        reasoning_effort TEXT NOT NULL
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
    _connection.execute('PRAGMA user_version = 1;');
  }

  /// 新增 Prompt 模板和固定顺序提示词序列表。
  ///
  /// 子项（messages / steps）以 JSON 数组字符串存储，因为它们始终作为整体读写，
  /// 无需按子项单独查询。
  void _migrateV2() {
    _connection.execute('''
      CREATE TABLE IF NOT EXISTS prompt_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        system_prompt TEXT NOT NULL DEFAULT '',
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
    _connection.execute('PRAGMA user_version = 2;');
  }

  /// 新增收藏夹和收藏记录表。
  void _migrateV3() {
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
    _connection.execute('PRAGMA user_version = 3;');
  }
}
