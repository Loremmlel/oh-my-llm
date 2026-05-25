import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../features/chat/domain/models/chat_conversation.dart';

/// 后台 Isolate 入口：打开独立 sqlite3 连接，处理全量写入请求。
@pragma('vm:entry-point')
void chatWriterEntryPoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  sqlite.Database? db;
  final pendingWrites = <List<dynamic>>[];

  commandPort.listen((message) {
    if (message is String) {
      try {
        db?.close();
      } catch (_) {}
      try {
        db = sqlite.sqlite3.open(message);
        final currentDb = db!;
        currentDb.execute('PRAGMA foreign_keys = ON;');
        if (message != ':memory:') {
          currentDb.execute('PRAGMA journal_mode = WAL;');
        }
        currentDb.execute('PRAGMA busy_timeout = 5000;');
        for (final pending in pendingWrites) {
          _executeSaveConversations(currentDb, pending);
        }
        pendingWrites.clear();
      } catch (_) {
        db = null; // 打开失败，重置引用避免后续在已关闭连接上操作
        // 初始化失败，下次写入请求前会重新初始化
      }
    } else if (message is List) {
      final currentDb = db;
      if (currentDb != null) {
        try {
          _executeSaveConversations(currentDb, message);
        } catch (e) {
          // ignore: avoid_print
          print('[BackgroundWriter] 写入失败: $e');
        }
      } else {
        pendingWrites.add(message);
      }
    }
  });
}

void _executeSaveConversations(sqlite.Database db, List<dynamic> conversationsJson) {
  final conversations = conversationsJson
      .map((j) => ChatConversation.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList(growable: false);

  if (conversations.isEmpty) {
    return;
  }

  db.execute('BEGIN IMMEDIATE;');
  try {
    final conversationStatement = db.prepare('''
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
        id, conversation_id, title, content, parent_checkpoint_id,
        covered_until_message_id, source_memory_prompt_name, created_at
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
          normalized.autoRetryEnabled ? 1 : 0,
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
        for (final entry in normalized.selectedChildByParentId.entries) {
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
