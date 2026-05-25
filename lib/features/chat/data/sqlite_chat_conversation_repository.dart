import 'dart:convert';

import '../../../core/persistence/app_database.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import '../domain/models/chat_message.dart';
import 'chat_conversation_repository.dart';

/// 基于 SQLite 的会话持久化仓库，负责按表保存会话树与分支选择。
class SqliteChatConversationRepository implements ChatConversationRepository {
  const SqliteChatConversationRepository(this._database);

  final AppDatabase _database;

  @override
  List<ChatConversation> loadAll() {
    final conversationRows = _database.connection.select('''
      SELECT
        id,
        title,
        created_at,
        updated_at,
        selected_model_id,
        selected_checkpoint_id,
        selected_preset_prompt_id,
        reasoning_enabled,
        reasoning_effort,
        excluded_message_ids_json
      FROM conversations
      ORDER BY updated_at DESC
    ''');
    if (conversationRows.isEmpty) {
      return const [];
    }

    final messageRows = _database.connection.select('''
      SELECT
        id,
        conversation_id,
        node_index,
        parent_id,
        role,
        content,
        reasoning_content,
        assistant_model_display_name,
        applied_checkpoint_title,
        user_message_segments_json,
        created_at
      FROM messages
      ORDER BY conversation_id, node_index
    ''');
    final selectionRows = _database.connection.select('''
      SELECT conversation_id, parent_id, child_id
      FROM conversation_branch_selections
      ORDER BY conversation_id, parent_id
    ''');
    final checkpointRows = _database.connection.select('''
      SELECT
        id,
        conversation_id,
        title,
        content,
        parent_checkpoint_id,
        covered_until_message_id,
        source_memory_prompt_name,
        created_at
      FROM conversation_checkpoints
      ORDER BY conversation_id, created_at ASC
    ''');

    final nodesByConversationId = <String, List<ChatMessage>>{};
    for (final row in messageRows) {
      final conversationId = row['conversation_id'] as String;
      nodesByConversationId
          .putIfAbsent(conversationId, () => <ChatMessage>[])
          .add(
            ChatMessage(
              id: row['id'] as String,
              role: ChatMessageRole.values.firstWhere(
                (role) => role.apiValue == row['role'],
              ),
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              parentId: row['parent_id'] as String?,
              reasoningContent: row['reasoning_content'] as String? ?? '',
              assistantModelDisplayName:
                  row['assistant_model_display_name'] as String? ?? '',
              appliedCheckpointTitle:
                  row['applied_checkpoint_title'] as String? ?? '',
              userMessageSegments:
                  (jsonDecode(
                            row['user_message_segments_json'] as String? ??
                                '[]',
                          )
                          as List)
                      .map(
                        (segment) => UserMessageSegment.fromJson(
                          Map<String, dynamic>.from(segment as Map),
                        ),
                      )
                      .toList(growable: false),
            ),
          );
    }

    final selectionsByConversationId = <String, Map<String, String>>{};
    for (final row in selectionRows) {
      final conversationId = row['conversation_id'] as String;
      selectionsByConversationId.putIfAbsent(
        conversationId,
        () => <String, String>{},
      )[row['parent_id'] as String] = row['child_id'] as String;
    }

    final checkpointsByConversationId = <String, List<ChatCheckpoint>>{};
    for (final row in checkpointRows) {
      final conversationId = row['conversation_id'] as String;
      checkpointsByConversationId
          .putIfAbsent(conversationId, () => <ChatCheckpoint>[])
          .add(
            ChatCheckpoint(
              id: row['id'] as String,
              title: row['title'] as String,
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              parentCheckpointId: row['parent_checkpoint_id'] as String?,
              coveredUntilMessageId: row['covered_until_message_id'] as String?,
              sourceMemoryPromptName:
                  row['source_memory_prompt_name'] as String? ?? '',
            ),
          );
    }

    return conversationRows
        .map((row) => _buildConversation(
              row: row,
              nodes:
                  nodesByConversationId[row['id'] as String] ??
                  const <ChatMessage>[],
              selections:
                  selectionsByConversationId[row['id'] as String] ??
                  const <String, String>{},
              checkpoints:
                  checkpointsByConversationId[row['id'] as String] ??
                  const <ChatCheckpoint>[],
            ))
        .toList(growable: false);
  }

  @override
  ChatConversation? loadConversation(String id) {
    final rows = _database.connection.select(
      '''
      SELECT
        id,
        title,
        created_at,
        updated_at,
        selected_model_id,
        selected_checkpoint_id,
        selected_preset_prompt_id,
        reasoning_enabled,
        reasoning_effort,
        excluded_message_ids_json
      FROM conversations
      WHERE id = ?
      ''',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    final conversationRow = rows.first;

    final messageRows = _database.connection.select(
      '''
      SELECT
        id,
        conversation_id,
        node_index,
        parent_id,
        role,
        content,
        reasoning_content,
        assistant_model_display_name,
        applied_checkpoint_title,
        user_message_segments_json,
        created_at
      FROM messages
      WHERE conversation_id = ?
      ORDER BY node_index
      ''',
      [id],
    );
    final nodes = messageRows
        .map(
          (row) => ChatMessage(
            id: row['id'] as String,
            role: ChatMessageRole.values.firstWhere(
              (role) => role.apiValue == row['role'],
            ),
            content: row['content'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            parentId: row['parent_id'] as String?,
            reasoningContent: row['reasoning_content'] as String? ?? '',
            assistantModelDisplayName:
                row['assistant_model_display_name'] as String? ?? '',
            appliedCheckpointTitle:
                row['applied_checkpoint_title'] as String? ?? '',
            userMessageSegments:
                (jsonDecode(
                          row['user_message_segments_json'] as String? ?? '[]',
                        )
                        as List)
                    .map(
                      (segment) => UserMessageSegment.fromJson(
                        Map<String, dynamic>.from(segment as Map),
                      ),
                    )
                    .toList(growable: false),
          ),
        )
        .toList(growable: false);

    final selectionRows = _database.connection.select(
      'SELECT conversation_id, parent_id, child_id FROM conversation_branch_selections WHERE conversation_id = ?',
      [id],
    );
    final selections = <String, String>{};
    for (final row in selectionRows) {
      selections[row['parent_id'] as String] = row['child_id'] as String;
    }

    final checkpointRows = _database.connection.select(
      '''
      SELECT
        id,
        conversation_id,
        title,
        content,
        parent_checkpoint_id,
        covered_until_message_id,
        source_memory_prompt_name,
        created_at
      FROM conversation_checkpoints
      WHERE conversation_id = ?
      ORDER BY created_at ASC
      ''',
      [id],
    );
    final checkpoints = checkpointRows
        .map(
          (row) => ChatCheckpoint(
            id: row['id'] as String,
            title: row['title'] as String,
            content: row['content'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            parentCheckpointId: row['parent_checkpoint_id'] as String?,
            coveredUntilMessageId: row['covered_until_message_id'] as String?,
            sourceMemoryPromptName:
                row['source_memory_prompt_name'] as String? ?? '',
          ),
        )
        .toList(growable: false);

    return _buildConversation(
      row: conversationRow,
      nodes: nodes,
      selections: selections,
      checkpoints: checkpoints,
    );
  }

  ChatConversation _buildConversation({
    required Map<String, dynamic> row,
    required List<ChatMessage> nodes,
    required Map<String, String> selections,
    required List<ChatCheckpoint> checkpoints,
  }) {
    return ChatConversation(
      id: row['id'] as String,
      title: row['title'] as String?,
      messages: const <ChatMessage>[],
      messageNodes: List.unmodifiable(nodes),
      selectedChildByParentId: Map.unmodifiable(selections),
      checkpoints: List.unmodifiable(checkpoints),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      selectedModelId: row['selected_model_id'] as String?,
      selectedCheckpointId: row['selected_checkpoint_id'] as String?,
      selectedPresetPromptId: row['selected_preset_prompt_id'] as String?,
      reasoningEnabled: (row['reasoning_enabled'] as int) == 1,
      reasoningEffort: ReasoningEffort.values.firstWhere(
        (effort) => effort.apiValue == row['reasoning_effort'],
        orElse: () => ReasoningEffort.medium,
      ),
      excludedMessageIds:
          (jsonDecode(row['excluded_message_ids_json'] as String? ?? '[]')
                  as List)
              .whereType<String>()
              .toSet()
              .toList(growable: false),
    );
  }

  @override
  Future<void> deleteConversations(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final db = _database.connection;
    final placeholders = ids.map((_) => '?').join(',');
    final params = List<dynamic>.from(ids);
    db.execute('BEGIN IMMEDIATE;');
    try {
      db.execute(
        'DELETE FROM conversation_checkpoints WHERE conversation_id IN ($placeholders)',
        params,
      );
      db.execute(
        'DELETE FROM conversation_branch_selections WHERE conversation_id IN ($placeholders)',
        params,
      );
      db.execute(
        'DELETE FROM messages WHERE conversation_id IN ($placeholders)',
        params,
      );
      db.execute(
        'DELETE FROM conversations WHERE id IN ($placeholders)',
        params,
      );
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  List<ChatConversationSummary> loadHistorySummaries({String keyword = ''}) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final hasKeyword = normalizedKeyword.isNotEmpty;
    final likeKeyword = '%$normalizedKeyword%';
    final rows = _database.connection.select(
      '''
      SELECT
        c.id,
        c.title,
        c.updated_at,
        COALESCE((
          SELECT m.content
          FROM messages m
          WHERE m.conversation_id = c.id
            AND m.role = 'user'
          ORDER BY m.node_index ASC
          LIMIT 1
        ), '') AS first_user_message_preview,
        COALESCE((
          SELECT m.content
          FROM messages m
          WHERE m.conversation_id = c.id
            AND m.role = 'user'
          ORDER BY m.node_index DESC
          LIMIT 1
        ), '') AS latest_user_message_preview
      FROM conversations c
      WHERE (
        EXISTS (
          SELECT 1
          FROM messages m
          WHERE m.conversation_id = c.id
        )
        OR EXISTS (
          SELECT 1
          FROM conversation_checkpoints ch
          WHERE ch.conversation_id = c.id
        )
      )
        AND (
          ? = 0
          OR LOWER(COALESCE(c.title, '')) LIKE ?
          OR EXISTS (
            SELECT 1
            FROM messages m
            WHERE m.conversation_id = c.id
              AND m.role = 'user'
              AND LOWER(m.content) LIKE ?
          )
        )
      ORDER BY c.updated_at DESC
      ''',
      [hasKeyword ? 1 : 0, likeKeyword, likeKeyword],
    );

    return rows
        .map((row) {
          return ChatConversationSummary(
            id: row['id'] as String,
            title: row['title'] as String?,
            updatedAt: DateTime.parse(row['updated_at'] as String),
            firstUserMessagePreview:
                row['first_user_message_preview'] as String? ?? '',
            latestUserMessagePreview:
                row['latest_user_message_preview'] as String? ?? '',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) async {
    if (conversations.isEmpty) {
      return;
    }

    final db = _database.connection;
    db.execute('BEGIN IMMEDIATE;');
    try {
      final conversationStatement = db.prepare('''
        INSERT INTO conversations (
          id, title, created_at, updated_at,
          selected_model_id, selected_checkpoint_id, selected_preset_prompt_id,
          reasoning_enabled, reasoning_effort, excluded_message_ids_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          updated_at = excluded.updated_at,
          selected_model_id = excluded.selected_model_id,
          selected_checkpoint_id = excluded.selected_checkpoint_id,
          selected_preset_prompt_id = excluded.selected_preset_prompt_id,
          reasoning_enabled = excluded.reasoning_enabled,
          reasoning_effort = excluded.reasoning_effort,
          excluded_message_ids_json = excluded.excluded_message_ids_json
      ''');
      final messageStatement = db.prepare('''
        INSERT INTO messages (
          id, conversation_id, node_index, parent_id, role,
          content, reasoning_content, assistant_model_display_name,
          applied_checkpoint_title, user_message_segments_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      final selectionStatement = db.prepare('''
        INSERT INTO conversation_branch_selections (
          conversation_id, parent_id, child_id
        ) VALUES (?, ?, ?)
      ''');
      final checkpointStatement = db.prepare('''
        INSERT INTO conversation_checkpoints (
          id, conversation_id, title, content,
          parent_checkpoint_id, covered_until_message_id,
          source_memory_prompt_name, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        for (final conversation in conversations) {
          final normalized = ChatConversation.fromJson(conversation.toJson());

          conversationStatement.execute([
            normalized.id,
            normalized.title,
            normalized.createdAt.toIso8601String(),
            normalized.updatedAt.toIso8601String(),
            normalized.selectedModelId,
            normalized.selectedCheckpointId,
            normalized.selectedPresetPromptId,
            normalized.reasoningEnabled ? 1 : 0,
            normalized.reasoningEffort.apiValue,
            jsonEncode(normalized.excludedMessageIds),
          ]);

          db.execute(
            'DELETE FROM messages WHERE conversation_id = ?',
            [normalized.id],
          );
          db.execute(
            'DELETE FROM conversation_branch_selections WHERE conversation_id = ?',
            [normalized.id],
          );
          db.execute(
            'DELETE FROM conversation_checkpoints WHERE conversation_id = ?',
            [normalized.id],
          );

          for (
            var nodeIndex = 0;
            nodeIndex < normalized.messageNodes.length;
            nodeIndex += 1
          ) {
            final message = normalized.messageNodes[nodeIndex];
            messageStatement.execute([
              message.id,
              normalized.id,
              nodeIndex,
              message.parentId,
              message.role.apiValue,
              message.content,
              message.reasoningContent,
              message.assistantModelDisplayName,
              message.appliedCheckpointTitle,
              jsonEncode(
                message.userMessageSegments
                    .map((segment) => segment.toJson())
                    .toList(),
              ),
              message.createdAt.toIso8601String(),
            ]);
          }
          for (final entry
              in normalized.selectedChildByParentId.entries) {
            selectionStatement.execute([
              normalized.id,
              entry.key,
              entry.value,
            ]);
          }
          for (final checkpoint in normalized.checkpoints) {
            checkpointStatement.execute([
              checkpoint.id,
              normalized.id,
              checkpoint.title,
              checkpoint.content,
              checkpoint.parentCheckpointId,
              checkpoint.coveredUntilMessageId,
              checkpoint.sourceMemoryPromptName,
              checkpoint.createdAt.toIso8601String(),
            ]);
          }
        }
      } finally {
        conversationStatement.close();
        messageStatement.close();
        selectionStatement.close();
        checkpointStatement.close();
      }

      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}
