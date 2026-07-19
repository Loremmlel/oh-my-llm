import '../../../core/persistence/app_database.dart';
import '../domain/models/favorite.dart';
import 'favorites_repository.dart';

/// 收藏记录的 SQLite 读写仓库。
class SqliteFavoritesRepository implements FavoritesRepository {
  const SqliteFavoritesRepository(this._database);

  final AppDatabase _database;

  @override
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

  @override
  void save(Favorite favorite) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO favorites '
      '(id, collection_id, user_message_content, assistant_content, '
      'assistant_reasoning_content, assistant_model_display_name, source_conversation_id, '
      'source_conversation_title, source_assistant_message_id, title, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        favorite.id,
        favorite.collectionId,
        favorite.userMessageContent,
        favorite.assistantContent,
        favorite.assistantReasoningContent,
        favorite.assistantModelDisplayName,
        favorite.sourceConversationId,
        favorite.sourceConversationTitle,
        favorite.sourceAssistantMessageId,
        favorite.title,
        favorite.createdAt.toIso8601String(),
      ],
    );
  }

  @override
  void delete(String favoriteId) {
    _database.connection.execute('DELETE FROM favorites WHERE id = ?;', [
      favoriteId,
    ]);
  }

  @override
  void moveToCollection(String favoriteId, String? collectionId) {
    _database.connection.execute(
      'UPDATE favorites SET collection_id = ? WHERE id = ?;',
      [collectionId, favoriteId],
    );
  }

  @override
  void updateTitle(String favoriteId, String? title) {
    _database.connection.execute(
      'UPDATE favorites SET title = ? WHERE id = ?;',
      [title, favoriteId],
    );
  }

  @override
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
          row['assistant_reasoning_content'] as String,
      assistantModelDisplayName:
          row['assistant_model_display_name'] as String,
      sourceConversationId: row['source_conversation_id'] as String?,
      sourceConversationTitle: row['source_conversation_title'] as String?,
      sourceAssistantMessageId:
          row['source_assistant_message_id'] as String?,
      title: row['title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
