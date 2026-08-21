import 'package:oh_my_llm/core/persistence/app_database.dart';
import '../domain/models/favorite.dart';
import '../domain/models/favorite_page.dart';
import '../application/ports/favorites_repository.dart';

/// 收藏记录的 SQLite 读写仓库。
class SqliteFavoritesRepository implements FavoritesRepository {
  const SqliteFavoritesRepository(this._database);

  final AppDatabase _database;

  @override
  FavoritePage loadPage({
    required String collectionId,
    required int limit,
    required int offset,
  }) {
    if (collectionId.isEmpty) {
      throw ArgumentError('collectionId 不能为空', 'collectionId');
    }
    if (limit <= 0) {
      throw RangeError.range(limit, 1, null, 'limit');
    }
    if (offset < 0) {
      throw RangeError.range(offset, 0, null, 'offset');
    }

    final totalItems =
        _database.connection.select(
              'SELECT COUNT(*) AS c FROM favorites WHERE collection_id = ?;',
              [collectionId],
            ).single['c']
            as int;
    final rows = _database.connection.select(
      'SELECT * FROM favorites WHERE collection_id = ? '
      'ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?;',
      [collectionId, limit, offset],
    );

    return FavoritePage(
      items: rows.map(_rowToFavorite).toList(growable: false),
      totalItems: totalItems,
    );
  }

  @override
  Favorite? loadById(String favoriteId) {
    final rows = _database.connection.select(
      'SELECT * FROM favorites WHERE id = ? LIMIT 1;',
      [favoriteId],
    );
    if (rows.isEmpty) return null;
    return _rowToFavorite(rows.first);
  }

  @override
  Favorite? findByAssistantContent(String assistantContent) {
    final rows = _database.connection.select(
      'SELECT * FROM favorites WHERE assistant_content = ? '
      'ORDER BY created_at DESC, id DESC LIMIT 1;',
      [assistantContent],
    );
    if (rows.isEmpty) return null;
    return _rowToFavorite(rows.first);
  }

  @override
  Set<String> loadFavoritedAssistantContents(
    Iterable<String> assistantContents,
  ) {
    final contents = assistantContents.toSet();
    // 空集合不生成 IN ()。
    if (contents.isEmpty) return const {};

    final placeholders = List.filled(contents.length, '?').join(', ');
    final rows = _database.connection.select(
      'SELECT DISTINCT assistant_content FROM favorites '
      'WHERE assistant_content IN ($placeholders);',
      contents.toList(growable: false),
    );
    return {for (final row in rows) row['assistant_content'] as String};
  }

  @override
  void save(Favorite favorite) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO favorites '
      '(id, collection_id, user_message_content, assistant_content, '
      'assistant_reasoning_content, assistant_model_display_name, source_conversation_id, '
      'source_conversation_title, source_assistant_message_id, title, created_at, '
      'collection_assigned_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
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
        favorite.collectionAssignedAt.toIso8601String(),
      ],
    );
  }

  @override
  int deleteMany(Set<String> favoriteIds) {
    if (favoriteIds.isEmpty) return 0;
    return _executeBulkWrite('DELETE FROM favorites WHERE id IN ', favoriteIds);
  }

  @override
  int moveMany(
    Set<String> favoriteIds, {
    required String targetCollectionId,
    required DateTime assignedAt,
  }) {
    if (favoriteIds.isEmpty) return 0;
    final connection = _database.connection;
    connection.execute('BEGIN;');
    try {
      // 单条 UPDATE 即可覆盖整批 ID，事务只为保证原子语义。
      final affected = _executeBulkWrite(
        'UPDATE favorites SET collection_id = ?, collection_assigned_at = ? WHERE id IN ',
        favoriteIds,
        leadingParams: [targetCollectionId, assignedAt.toIso8601String()],
      );
      connection.execute('COMMIT;');
      return affected;
    } catch (_) {
      connection.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  void updateTitle(String favoriteId, String? title) {
    _database.connection.execute(
      'UPDATE favorites SET title = ? WHERE id = ?;',
      [title, favoriteId],
    );
  }

  /// 用受控 placeholders 执行带 IN 子句的写语句，返回受影响行数。
  int _executeBulkWrite(
    String prefixSql,
    Set<String> ids, {
    List<Object?> leadingParams = const [],
  }) {
    final connection = _database.connection;
    final statement = connection.prepare(
      '$prefixSql(${List.filled(ids.length, '?').join(', ')});',
    );
    try {
      statement.execute([...leadingParams, ...ids]);
      return connection.select('SELECT changes() AS c;').single['c'] as int;
    } finally {
      statement.close();
    }
  }

  Favorite _rowToFavorite(Map<String, dynamic> row) {
    return Favorite(
      id: row['id'] as String,
      collectionId: row['collection_id'] as String,
      collectionAssignedAt: DateTime.parse(
        row['collection_assigned_at'] as String,
      ),
      userMessageContent: row['user_message_content'] as String,
      assistantContent: row['assistant_content'] as String,
      assistantReasoningContent: row['assistant_reasoning_content'] as String,
      assistantModelDisplayName: row['assistant_model_display_name'] as String,
      sourceConversationId: row['source_conversation_id'] as String?,
      sourceConversationTitle: row['source_conversation_title'] as String?,
      sourceAssistantMessageId: row['source_assistant_message_id'] as String?,
      title: row['title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
