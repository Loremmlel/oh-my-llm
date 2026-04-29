import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/app_database_provider.dart';
import '../domain/models/favorite.dart';

/// 收藏记录 SQLite 仓库 Provider。
final favoritesRepositoryProvider = Provider<SqliteFavoritesRepository>(
  (ref) => SqliteFavoritesRepository(ref.watch(appDatabaseProvider)),
);

/// 收藏记录的 SQLite 读写仓库。
class SqliteFavoritesRepository {
  const SqliteFavoritesRepository(this._database);

  final AppDatabase _database;

  /// 按收藏时间降序返回全部收藏记录，可选按收藏夹筛选。
  ///
  /// - [collectionId] 为 null：返回所有收藏
  /// - [collectionId] 为空字符串 `''`：返回未分类（collection_id IS NULL）
  /// - 其他值：按该 ID 过滤
  List<Favorite> loadAll({String? collectionId}) {
    if (collectionId == null) {
      final rows = _database.connection.select(
        'SELECT * FROM favorites ORDER BY created_at DESC;',
      );
      return rows.map(_rowToFavorite).toList(growable: false);
    }

    if (collectionId.isEmpty) {
      final rows = _database.connection.select(
        'SELECT * FROM favorites WHERE collection_id IS NULL ORDER BY created_at DESC;',
      );
      return rows.map(_rowToFavorite).toList(growable: false);
    }

    final rows = _database.connection.select(
      'SELECT * FROM favorites WHERE collection_id = ? ORDER BY created_at DESC;',
      [collectionId],
    );
    return rows.map(_rowToFavorite).toList(growable: false);
  }

  /// 保存单条收藏（INSERT OR REPLACE）。
  void save(Favorite favorite) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO favorites '
      '(id, collection_id, user_message_content, assistant_content, '
      'assistant_reasoning_content, assistant_model_display_name, source_conversation_id, '
      'source_conversation_title, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        favorite.id,
        favorite.collectionId,
        favorite.userMessageContent,
        favorite.assistantContent,
        favorite.assistantReasoningContent,
        favorite.assistantModelDisplayName,
        favorite.sourceConversationId,
        favorite.sourceConversationTitle,
        favorite.createdAt.toIso8601String(),
      ],
    );
  }

  /// 删除指定收藏记录。
  void delete(String favoriteId) {
    _database.connection.execute('DELETE FROM favorites WHERE id = ?;', [
      favoriteId,
    ]);
  }

  /// 将指定收藏移动到另一个收藏夹（null 表示未分类）。
  void moveToCollection(String favoriteId, String? collectionId) {
    _database.connection.execute(
      'UPDATE favorites SET collection_id = ? WHERE id = ?;',
      [collectionId, favoriteId],
    );
  }

  /// 检查指定助手消息内容是否已存在收藏（以内容做匹配）。
  bool existsByAssistantContent(String assistantContent) {
    final rows = _database.connection.select(
      'SELECT 1 FROM favorites WHERE assistant_content = ? LIMIT 1;',
      [assistantContent],
    );
    return rows.isNotEmpty;
  }

  Favorite _rowToFavorite(Map<String, dynamic> row) {
    return Favorite(
      id: row['id'] as String,
      collectionId: row['collection_id'] as String?,
      userMessageContent: row['user_message_content'] as String,
      assistantContent: row['assistant_content'] as String,
      assistantReasoningContent:
          (row['assistant_reasoning_content'] as String?) ?? '',
      assistantModelDisplayName:
          (row['assistant_model_display_name'] as String?) ?? '匿名模型',
      sourceConversationId: row['source_conversation_id'] as String?,
      sourceConversationTitle: row['source_conversation_title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
