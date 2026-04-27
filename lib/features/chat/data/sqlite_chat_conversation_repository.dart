import '../../../core/persistence/app_database.dart';
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
        selected_prompt_template_id,
        reasoning_enabled,
        reasoning_effort
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
        created_at
      FROM messages
      ORDER BY conversation_id, node_index
    ''');
    final selectionRows = _database.connection.select('''
      SELECT conversation_id, parent_id, child_id
      FROM conversation_branch_selections
      ORDER BY conversation_id, parent_id
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

    return conversationRows
        .map((row) {
          final nodes =
              nodesByConversationId[row['id'] as String] ??
              const <ChatMessage>[];
          final selections =
              selectionsByConversationId[row['id'] as String] ??
              const <String, String>{};
          final draft = ChatConversation(
            id: row['id'] as String,
            title: row['title'] as String?,
            messages: const <ChatMessage>[],
            messageNodes: List.unmodifiable(nodes),
            selectedChildByParentId: Map.unmodifiable(selections),
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
            selectedModelId: row['selected_model_id'] as String?,
            selectedPromptTemplateId:
                row['selected_prompt_template_id'] as String?,
            reasoningEnabled: (row['reasoning_enabled'] as int) == 1,
            reasoningEffort: ReasoningEffort.values.firstWhere(
              (effort) => effort.apiValue == row['reasoning_effort'],
              orElse: () => ReasoningEffort.medium,
            ),
          );
          return draft.copyWith(messages: draft.messages);
        })
        .toList(growable: false);
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
      WHERE EXISTS (
        SELECT 1
        FROM messages m
        WHERE m.conversation_id = c.id
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
  Future<void> saveAll(List<ChatConversation> conversations) async {
    _database.connection.execute('BEGIN IMMEDIATE;');
    try {
      _database.connection.execute(
        'DELETE FROM conversation_branch_selections;',
      );
      _database.connection.execute('DELETE FROM messages;');
      _database.connection.execute('DELETE FROM conversations;');

      final conversationStatement = _database.connection.prepare('''
        INSERT INTO conversations (
          id,
          title,
          created_at,
          updated_at,
          selected_model_id,
          selected_prompt_template_id,
          reasoning_enabled,
          reasoning_effort
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      final messageStatement = _database.connection.prepare('''
        INSERT INTO messages (
          id,
          conversation_id,
          node_index,
          parent_id,
          role,
          content,
          reasoning_content,
          created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      final selectionStatement = _database.connection.prepare('''
        INSERT INTO conversation_branch_selections (
          conversation_id,
          parent_id,
          child_id
        ) VALUES (?, ?, ?)
      ''');
      try {
        for (final conversation in conversations) {
          final normalizedConversation = ChatConversation.fromJson(
            conversation.toJson(),
          );
          conversationStatement.execute([
            normalizedConversation.id,
            normalizedConversation.title,
            normalizedConversation.createdAt.toIso8601String(),
            normalizedConversation.updatedAt.toIso8601String(),
            normalizedConversation.selectedModelId,
            normalizedConversation.selectedPromptTemplateId,
            normalizedConversation.reasoningEnabled ? 1 : 0,
            normalizedConversation.reasoningEffort.apiValue,
          ]);
          for (
            var nodeIndex = 0;
            nodeIndex < normalizedConversation.messageNodes.length;
            nodeIndex += 1
          ) {
            final message = normalizedConversation.messageNodes[nodeIndex];
            messageStatement.execute([
              message.id,
              normalizedConversation.id,
              nodeIndex,
              message.parentId,
              message.role.apiValue,
              message.content,
              message.reasoningContent,
              message.createdAt.toIso8601String(),
            ]);
          }
          for (final entry
              in normalizedConversation.selectedChildByParentId.entries) {
            selectionStatement.execute([
              normalizedConversation.id,
              entry.key,
              entry.value,
            ]);
          }
        }
      } finally {
        conversationStatement.dispose();
        messageStatement.dispose();
        selectionStatement.dispose();
      }

      _database.connection.execute('COMMIT;');
    } catch (_) {
      _database.connection.execute('ROLLBACK;');
      rethrow;
    }
  }
}
