import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
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
  /// 历史 V9→V13 逐级迁移已退役；v13 是唯一临时支持的旧基线
  /// （v13→v14 收藏归属迁移），低于或高于该范围的数据库都会被显式拒绝打开。
  static const int currentSchemaVersion = 14;

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
  /// - `user_version == 13`：唯一临时支持的旧基线，执行 v13→v14 迁移；
  /// - 其余版本（更旧的遗留库或更新版本应用创建的库）显式拒绝，
  ///   避免仓库层在不兼容的 schema 上误读误写。
  void _initializeSchema() {
    final currentVersion =
        _connection.select('PRAGMA user_version;').single['user_version']
            as int;
    if (currentVersion == 0) {
      _createSchema();
      _connection.execute('PRAGMA user_version = $currentSchemaVersion;');
    } else if (currentVersion == currentSchemaVersion) {
      // 当前版本数据库，直接可用。
    } else if (currentVersion == 13) {
      _migrateFavoritesFromV13ToV14();
    } else {
      throw AppDatabaseSchemaVersionException(currentVersion);
    }
  }

  /// 播种系统"未分类"收藏夹；已存在时跳过（幂等）。
  void _seedSystemFavoriteCollection() {
    _connection.execute(
      'INSERT OR IGNORE INTO collections (id, name, created_at) VALUES (?, ?, ?);',
      [
        AppReservedEntities.uncategorizedFavoriteCollectionId,
        AppReservedEntities.uncategorizedFavoriteCollectionName,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  /// favorites 表 v14 结构；[tableName] 供迁移重建时使用中间表名。
  String _favoritesTableV14Ddl(String tableName) =>
      '''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        collection_id TEXT NOT NULL,
        user_message_content TEXT NOT NULL,
        assistant_content TEXT NOT NULL,
        assistant_reasoning_content TEXT NOT NULL DEFAULT '',
        source_conversation_id TEXT,
        source_conversation_title TEXT,
        source_assistant_message_id TEXT,
        created_at TEXT NOT NULL,
        assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
        title TEXT,
        collection_assigned_at TEXT NOT NULL,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE RESTRICT
      );
    ''';

  /// v13 → v14：把"未分类"从 null 归属语义升级为固定系统收藏夹。
  ///
  /// SQLite 无法原地修改列约束与外键动作，必须重建 favorites 表：
  /// 单事务内播种系统收藏夹、按新结构回填数据、校验外键后提交；
  /// 任一步失败整体回滚，原 v13 数据保持可读。
  void _migrateFavoritesFromV13ToV14() {
    _connection.execute('BEGIN;');
    try {
      // 按固定 ID 播种系统夹，不按名称复用可能存在的同名普通行。
      _seedSystemFavoriteCollection();

      _connection.execute(_favoritesTableV14Ddl('favorites_v14'));
      // null/空串/孤儿归属统一写入系统收藏夹；归属时间以收藏时间落定。
      _connection.execute(
        '''
        INSERT INTO favorites_v14 (
          id, collection_id, user_message_content, assistant_content,
          assistant_reasoning_content, source_conversation_id,
          source_conversation_title, source_assistant_message_id,
          created_at, assistant_model_display_name, title, collection_assigned_at
        )
        SELECT
          id,
          CASE
            WHEN collection_id IS NULL OR collection_id = '' THEN ?
            WHEN NOT EXISTS (
              SELECT 1 FROM collections WHERE collections.id = favorites.collection_id
            ) THEN ?
            ELSE collection_id
          END,
          user_message_content,
          assistant_content,
          assistant_reasoning_content,
          source_conversation_id,
          source_conversation_title,
          source_assistant_message_id,
          created_at,
          assistant_model_display_name,
          title,
          created_at
        FROM favorites;
        ''',
        [
          AppReservedEntities.uncategorizedFavoriteCollectionId,
          AppReservedEntities.uncategorizedFavoriteCollectionId,
        ],
      );
      // 先删旧表再建索引：索引名在库内唯一，旧表的 idx_favorites_created_at
      // 必须先随表删除才能在新表上重建同名索引。
      _connection.execute('DROP TABLE favorites;');
      _connection.execute('ALTER TABLE favorites_v14 RENAME TO favorites;');
      _connection.execute(
        'CREATE INDEX IF NOT EXISTS idx_favorites_created_at '
        'ON favorites(created_at DESC);',
      );
      _connection.execute(
        'CREATE INDEX IF NOT EXISTS idx_favorites_collection_created '
        'ON favorites(collection_id, created_at DESC, id DESC);',
      );
      _connection.execute(
        'CREATE INDEX IF NOT EXISTS idx_favorites_collection_assigned '
        'ON favorites(collection_id, collection_assigned_at DESC);',
      );

      final violations = _connection.select('PRAGMA foreign_key_check;');
      if (violations.isNotEmpty) {
        throw StateError('v13→v14 迁移后外键校验失败，已回滚');
      }
      _connection.execute('PRAGMA user_version = 14;');
      _connection.execute('COMMIT;');
    } catch (_) {
      _connection.execute('ROLLBACK;');
      rethrow;
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
    _connection.execute(_favoritesTableV14Ddl('favorites'));
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorites_created_at
      ON favorites(created_at DESC);
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorites_collection_created
      ON favorites(collection_id, created_at DESC, id DESC);
    ''');
    _connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorites_collection_assigned
      ON favorites(collection_id, collection_assigned_at DESC);
    ''');
    // 全新 schema 建完 collections/favorites 后立即播种系统收藏夹。
    _seedSystemFavoriteCollection();
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
