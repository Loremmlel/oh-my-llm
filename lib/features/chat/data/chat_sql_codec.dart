import 'dart:convert';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

// ── UPSERT SQL 常量 ────────────────────────────────────────────

const kConversationUpsertSql = '''
  INSERT INTO conversations (
    id, title, created_at, updated_at,
    selected_model_id, selected_checkpoint_id, selected_preset_prompt_id,
    reasoning_enabled, reasoning_effort, excluded_message_ids_json,
    auto_retry_enabled
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    updated_at = excluded.updated_at,
    selected_model_id = excluded.selected_model_id,
    selected_checkpoint_id = excluded.selected_checkpoint_id,
    selected_preset_prompt_id = excluded.selected_preset_prompt_id,
    reasoning_enabled = excluded.reasoning_enabled,
    reasoning_effort = excluded.reasoning_effort,
    excluded_message_ids_json = excluded.excluded_message_ids_json,
    auto_retry_enabled = excluded.auto_retry_enabled
''';

const kMessageUpsertSql = '''
  INSERT INTO messages (
    id, conversation_id, node_index, parent_id, role,
    content, reasoning_content, assistant_model_display_name,
    applied_checkpoint_title, user_message_segments_json,
    template_prompt_id, template_variable_values_json,
    finish_reason, created_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    node_index = excluded.node_index,
    content = excluded.content,
    reasoning_content = excluded.reasoning_content,
    assistant_model_display_name = excluded.assistant_model_display_name,
    applied_checkpoint_title = excluded.applied_checkpoint_title,
    user_message_segments_json = excluded.user_message_segments_json,
    template_prompt_id = excluded.template_prompt_id,
    template_variable_values_json = excluded.template_variable_values_json,
    finish_reason = excluded.finish_reason,
    created_at = excluded.created_at
''';

const kSelectionUpsertSql = '''
  INSERT INTO conversation_branch_selections (
    conversation_id, parent_id, child_id
  ) VALUES (?, ?, ?)
  ON CONFLICT(conversation_id, parent_id) DO UPDATE SET
    child_id = excluded.child_id
''';

const kCheckpointUpsertSql = '''
  INSERT INTO conversation_checkpoints (
    id, conversation_id, title, content, parent_checkpoint_id,
    covered_until_message_id, source_memory_prompt_name, created_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    content = excluded.content,
    parent_checkpoint_id = excluded.parent_checkpoint_id,
    covered_until_message_id = excluded.covered_until_message_id,
    source_memory_prompt_name = excluded.source_memory_prompt_name,
    created_at = excluded.created_at
''';

// ── SELECT 列列表常量 ──────────────────────────────────────────

/// messages 表的 SELECT 列列表，供 [loadAll] 和 [loadConversation] 共用。
///
/// 确保 `finish_reason` 等新增列不会因某个 SELECT 路径遗漏而漂移。
const kMessageSelectColumns = '''
  id, conversation_id, node_index, parent_id, role,
  content, reasoning_content, assistant_model_display_name,
  applied_checkpoint_title, user_message_segments_json,
  template_prompt_id, template_variable_values_json,
  finish_reason, created_at
''';

// ── 编解码函数 ─────────────────────────────────────────────────

/// 将 [ChatConversation] 编码为 conversations 表行参数。
List<Object?> conversationToRowParams(ChatConversation c) => [
      c.id,
      c.title,
      c.createdAt.toIso8601String(),
      c.updatedAt.toIso8601String(),
      c.selectedModelId,
      c.selectedCheckpointId,
      c.selectedPresetPromptId,
      c.reasoningEnabled ? 1 : 0,
      c.reasoningEffort.apiValue,
      jsonEncode(c.excludedMessageIds),
      c.autoRetryEnabled ? 1 : 0,
    ];

/// 将 [ChatMessage] 编码为 messages 表行参数。
List<Object?> messageToRowParams(
  ChatMessage m,
  String conversationId,
  int nodeIndex,
) =>
    [
      m.id,
      conversationId,
      nodeIndex,
      m.parentId,
      m.role.apiValue,
      m.content,
      m.reasoningContent,
      m.assistantModelDisplayName,
      m.appliedCheckpointTitle,
      jsonEncode(m.userMessageSegments.map((s) => s.toJson()).toList()),
      m.templatePromptId,
      jsonEncode(m.templateVariableValues),
      m.finishReason,
      m.createdAt.toIso8601String(),
    ];

/// 将 [ChatCheckpoint] 编码为 conversation_checkpoints 表行参数。
List<Object?> checkpointToRowParams(ChatCheckpoint cp, String conversationId) =>
    [
      cp.id,
      conversationId,
      cp.title,
      cp.content,
      cp.parentCheckpointId,
      cp.coveredUntilMessageId,
      cp.sourceMemoryPromptName,
      cp.createdAt.toIso8601String(),
    ];

// ── 核心写入函数 ───────────────────────────────────────────────

/// 执行会话全量保存（核心逻辑，前台 [SqliteChatConversationRepository]
/// 与后台 writer Isolate 共用）。
///
/// 对每个会话先 UPSERT conversations 行，再 DELETE 旧消息/分支选择/检查点，
/// 最后 INSERT 当前消息树。整个操作在 `BEGIN IMMEDIATE` 事务中完成。
void executeSaveConversations(
  sqlite.Database db,
  List<ChatConversation> conversations,
) {
  if (conversations.isEmpty) return;

  db.execute('BEGIN IMMEDIATE;');
  try {
    final convStmt = db.prepare(kConversationUpsertSql);
    final msgStmt = db.prepare(kMessageUpsertSql);
    final selStmt = db.prepare(kSelectionUpsertSql);
    final cpStmt = db.prepare(kCheckpointUpsertSql);
    try {
      for (final c in conversations) {
        convStmt.execute(conversationToRowParams(c));

        db.execute('DELETE FROM messages WHERE conversation_id = ?', [c.id]);
        db.execute(
          'DELETE FROM conversation_branch_selections WHERE conversation_id = ?',
          [c.id],
        );
        db.execute(
          'DELETE FROM conversation_checkpoints WHERE conversation_id = ?',
          [c.id],
        );

        for (var i = 0; i < c.messageNodes.length; i++) {
          msgStmt.execute(messageToRowParams(c.messageNodes[i], c.id, i));
        }
        for (final e in c.selectedChildByParentId.entries) {
          selStmt.execute([c.id, e.key, e.value]);
        }
        for (final cp in c.checkpoints) {
          cpStmt.execute(checkpointToRowParams(cp, c.id));
        }
      }
    } finally {
      convStmt.close();
      msgStmt.close();
      selStmt.close();
      cpStmt.close();
    }
    db.execute('COMMIT;');
  } catch (_) {
    db.execute('ROLLBACK;');
    rethrow;
  }
}

// ── Isolate 传输配对 ──────────────────────────────────────────

/// 将 [ChatConversation] 列表序列化为可跨 Isolate 传输的 JSON payload。
List<Map<String, dynamic>> conversationsToPayload(
  List<ChatConversation> conversations,
) =>
    conversations.map((c) => c.toJson()).toList(growable: false);

/// 从 JSON payload 反序列化并执行保存（供后台 worker Isolate 调用）。
void executeSaveFromPayload(sqlite.Database db, List<dynamic> payload) {
  final conversations = payload
      .map(
        (j) => ChatConversation.fromJson(Map<String, dynamic>.from(j as Map)),
      )
      .toList(growable: false);
  executeSaveConversations(db, conversations);
}
