import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:oh_my_llm/core/persistence/background_sqlite_writer.dart'
    show executeSaveConversations;
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

/// 创建测试用的内存数据库，含 conversations / messages /
/// conversation_branch_selections / conversation_checkpoints 四张表。
sqlite.Database _createTestDb() {
  final db = sqlite.sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON;');

  // ── conversations（含 v1 → v8 累积列）──────
  db.execute('''
    CREATE TABLE conversations (
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

  // ── messages（含 v1 → v6 累积列）──────
  db.execute('''
    CREATE TABLE messages (
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
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    );
  ''');

  // ── conversation_branch_selections ──────
  db.execute('''
    CREATE TABLE conversation_branch_selections (
      conversation_id TEXT NOT NULL,
      parent_id TEXT NOT NULL,
      child_id TEXT NOT NULL,
      PRIMARY KEY (conversation_id, parent_id),
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    );
  ''');

  // ── conversation_checkpoints ──────
  db.execute('''
    CREATE TABLE conversation_checkpoints (
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

  return db;
}

/// 构造一个包含线性消息的会话对象。
///
/// 消息按顺序自动建立 `parentId` 链，首个消息的 `parentId` 为 `__root__`。
ChatConversation _buildConversation({
  required String id,
  String? title,
  required List<ChatMessage> messages,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? selectedModelId,
  String? selectedCheckpointId,
  String? selectedPresetPromptId,
  bool reasoningEnabled = false,
  ReasoningEffort reasoningEffort = ReasoningEffort.medium,
  bool autoRetryEnabled = false,
  List<String> excludedMessageIds = const [],
}) {
  final now = DateTime.now();
  return ChatConversation(
    id: id,
    title: title,
    messages: messages,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    selectedModelId: selectedModelId,
    selectedCheckpointId: selectedCheckpointId,
    selectedPresetPromptId: selectedPresetPromptId,
    reasoningEnabled: reasoningEnabled,
    reasoningEffort: reasoningEffort,
    autoRetryEnabled: autoRetryEnabled,
    excludedMessageIds: excludedMessageIds,
  );
}

/// 构造一条测试消息。
ChatMessage _buildMessage({
  required String id,
  String? parentId,
  required ChatMessageRole role,
  required String content,
  DateTime? createdAt,
  String reasoningContent = '',
  String assistantModelDisplayName = '',
  String appliedCheckpointTitle = '',
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: content,
    createdAt: createdAt ?? DateTime.now(),
    parentId: parentId,
    reasoningContent: reasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    appliedCheckpointTitle: appliedCheckpointTitle,
  );
}

/// 将 ChatConversation 转为 executeSaveConversations 需要的 JSON 列表格式。
List<dynamic> _jsonify(ChatConversation conversation) {
  return [conversation.toJson()];
}

/// 将多个 ChatConversation 转为 JSON 列表。
List<dynamic> _jsonifyMany(List<ChatConversation> conversations) {
  return conversations.map((c) => c.toJson()).toList();
}

void main() {
  group('executeSaveConversations UPSERT & cleanup', () {
    // ────────────────────────────────────────────
    // 1. UPSERT 幂等性：相同 ID 消息更新不重复
    // ────────────────────────────────────────────
    test('UPSERT idempotency: same ID message updated not duplicated', () {
      final db = _createTestDb();
      try {
        final now = DateTime.now();
        final conv = _buildConversation(
          id: 'conv-1',
          title: '测试对话',
          createdAt: now,
          updatedAt: now,
          messages: [
            _buildMessage(
              id: 'msg-1',
              role: ChatMessageRole.user,
              content: '你好',
              createdAt: now,
            ),
            _buildMessage(
              id: 'msg-2',
              role: ChatMessageRole.assistant,
              content: '你好！有什么可以帮助你的？',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        );

        // 第一次写入
        executeSaveConversations(db, _jsonify(conv));

        // 修改 msg-2 的内容，保持 id 不变
        final modifiedConv = _buildConversation(
          id: 'conv-1',
          title: '测试对话',
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 1)),
          messages: [
            _buildMessage(
              id: 'msg-1',
              role: ChatMessageRole.user,
              content: '你好',
              createdAt: now,
            ),
            _buildMessage(
              id: 'msg-2',
              role: ChatMessageRole.assistant,
              content: '你好主人喵~',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        );

        // 第二次写入
        executeSaveConversations(db, _jsonify(modifiedConv));

        // 验证消息总数仍为 2
        final rowCount = db
            .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-1';")
            .single['cnt'] as int;
        expect(rowCount, equals(2));

        // 验证 msg-2 的内容已更新为新的内容
        final updatedMsg = db
            .select("SELECT content FROM messages WHERE id = 'msg-2';")
            .single;
        expect(updatedMsg['content'], equals('你好主人喵~'));

        // 验证 conversations 表也仅有一行
        final convCount = db
            .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-1';")
            .single['cnt'] as int;
        expect(convCount, equals(1));
      } finally {
        db.close();
      }
    });

    // ────────────────────────────────────────────
    // 2. Ghost row cleanup：消息减少时旧行被清理
    // ────────────────────────────────────────────
    test('Ghost row cleanup: removed message gone after re-save', () {
      final db = _createTestDb();
      try {
        final now = DateTime.now();
        final conv = _buildConversation(
          id: 'conv-1',
          title: '三消息对话',
          createdAt: now,
          updatedAt: now,
          messages: [
            _buildMessage(
              id: 'msg-a',
              role: ChatMessageRole.user,
              content: 'Hello',
              createdAt: now,
            ),
            _buildMessage(
              id: 'msg-b',
              role: ChatMessageRole.assistant,
              content: 'Hi!',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
            _buildMessage(
              id: 'msg-c',
              role: ChatMessageRole.user,
              content: 'How are you?',
              createdAt: now.add(const Duration(seconds: 2)),
            ),
          ],
        );

        executeSaveConversations(db, _jsonify(conv));
        expect(
          db
              .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-1';")
              .single['cnt'],
          equals(3),
        );

        // 重新保存：只保留 2 条消息（msg-c 被移除）
        final slimConv = _buildConversation(
          id: 'conv-1',
          title: '两消息对话',
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 1)),
          messages: [
            _buildMessage(
              id: 'msg-a',
              role: ChatMessageRole.user,
              content: 'Hello',
              createdAt: now,
            ),
            _buildMessage(
              id: 'msg-b',
              role: ChatMessageRole.assistant,
              content: 'Hi!',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        );

        executeSaveConversations(db, _jsonify(slimConv));

        // 验证只剩 2 条消息
        final remaining = db
            .select("SELECT id FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
        expect(remaining.length, equals(2));
        expect(remaining[0]['id'], equals('msg-a'));
        expect(remaining[1]['id'], equals('msg-b'));

        // 验证 msg-c 已被删除
        final ghost = db
            .select("SELECT COUNT(*) AS cnt FROM messages WHERE id = 'msg-c';")
            .single['cnt'] as int;
        expect(ghost, equals(0));
      } finally {
        db.close();
      }
    });

    // ────────────────────────────────────────────
    // 3. node_index 更新：顺序和内容正确
    // ────────────────────────────────────────────
    test('node_index update: sequential indexes after re-save', () {
      final db = _createTestDb();
      try {
        final now = DateTime.now();
        final conv = _buildConversation(
          id: 'conv-1',
          title: '索引测试',
          createdAt: now,
          updatedAt: now,
          messages: [
            _buildMessage(
              id: 'm1',
              role: ChatMessageRole.user,
              content: 'First',
              createdAt: now,
            ),
            _buildMessage(
              id: 'm2',
              role: ChatMessageRole.assistant,
              content: 'Second',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
            _buildMessage(
              id: 'm3',
              role: ChatMessageRole.user,
              content: 'Third',
              createdAt: now.add(const Duration(seconds: 2)),
            ),
          ],
        );

        executeSaveConversations(db, _jsonify(conv));

        // 首次：验证 node_index 为 0, 1, 2
        var rows = db
            .select("SELECT id, node_index FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
        expect(rows[0]['id'], equals('m1'));
        expect(rows[0]['node_index'], equals(0));
        expect(rows[1]['id'], equals('m2'));
        expect(rows[1]['node_index'], equals(1));
        expect(rows[2]['id'], equals('m3'));
        expect(rows[2]['node_index'], equals(2));

        // 修改 m2 的内容，重新保存
        final modifiedConv = _buildConversation(
          id: 'conv-1',
          title: '索引测试',
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 1)),
          messages: [
            _buildMessage(
              id: 'm1',
              role: ChatMessageRole.user,
              content: 'First',
              createdAt: now,
            ),
            _buildMessage(
              id: 'm2',
              role: ChatMessageRole.assistant,
              content: 'Second (edited)',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
            _buildMessage(
              id: 'm3',
              role: ChatMessageRole.user,
              content: 'Third',
              createdAt: now.add(const Duration(seconds: 2)),
            ),
          ],
        );

        executeSaveConversations(db, _jsonify(modifiedConv));

        // 再次验证 node_index 仍为正确的 0, 1, 2 且内容已更新
        rows = db
            .select("SELECT id, node_index, content FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
        expect(rows.length, equals(3));
        expect(rows[0]['node_index'], equals(0));
        expect(rows[1]['node_index'], equals(1));
        expect(rows[1]['content'], equals('Second (edited)'));
        expect(rows[2]['node_index'], equals(2));
      } finally {
        db.close();
      }
    });

    // ────────────────────────────────────────────
    // 4. 事务原子性：写入成功则数据完整
    // ────────────────────────────────────────────
    test('Transaction atomicity: all-or-nothing consistency', () {
      final db = _createTestDb();
      try {
        final now = DateTime.now();
        final conv = _buildConversation(
          id: 'conv-tx',
          title: '原子性测试',
          createdAt: now,
          updatedAt: now,
          messages: [
            _buildMessage(
              id: 'tx-msg-1',
              role: ChatMessageRole.user,
              content: 'Atomic test',
              createdAt: now,
            ),
            _buildMessage(
              id: 'tx-msg-2',
              role: ChatMessageRole.assistant,
              content: 'Response',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        );

        executeSaveConversations(db, _jsonify(conv));

        // 验证 conversations 与 messages 同步存在
        final convRow = db
            .select("SELECT * FROM conversations WHERE id = 'conv-tx';");
        expect(convRow.length, equals(1));
        expect(convRow.single['title'], equals('原子性测试'));

        final msgRows = db
            .select("SELECT * FROM messages WHERE conversation_id = 'conv-tx';");
        expect(msgRows.length, equals(2));
        expect(msgRows[0]['id'], equals('tx-msg-1'));
        expect(msgRows[1]['id'], equals('tx-msg-2'));

        // 再次写入相同数据，验证 conversation 行仍唯一（UPSERT 未产生重复）
        executeSaveConversations(db, _jsonify(conv));
        final convCount = db
            .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-tx';")
            .single['cnt'] as int;
        expect(convCount, equals(1));
        final msgCount = db
            .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-tx';")
            .single['cnt'] as int;
        expect(msgCount, equals(2));
      } finally {
        db.close();
      }
    });

    // ────────────────────────────────────────────
    // 5. 多会话写入：两个会话同时持久化
    // ────────────────────────────────────────────
    test('Multi-conversation write: both persisted correctly', () {
      final db = _createTestDb();
      try {
        final now = DateTime.now();
        final convA = _buildConversation(
          id: 'conv-a',
          title: '会话 A',
          createdAt: now,
          updatedAt: now,
          messages: [
            _buildMessage(
              id: 'a-msg-1',
              role: ChatMessageRole.user,
              content: 'Message A1',
              createdAt: now,
            ),
            _buildMessage(
              id: 'a-msg-2',
              role: ChatMessageRole.assistant,
              content: 'Reply A1',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        );

        final convB = _buildConversation(
          id: 'conv-b',
          title: '会话 B',
          createdAt: now.add(const Duration(hours: 1)),
          updatedAt: now.add(const Duration(hours: 1)),
          messages: [
            _buildMessage(
              id: 'b-msg-1',
              role: ChatMessageRole.user,
              content: 'Message B1',
              createdAt: now.add(const Duration(hours: 1)),
            ),
            _buildMessage(
              id: 'b-msg-2',
              role: ChatMessageRole.assistant,
              content: 'Reply B1',
              createdAt: now.add(const Duration(hours: 1, seconds: 1)),
            ),
            _buildMessage(
              id: 'b-msg-3',
              role: ChatMessageRole.user,
              content: 'Message B2',
              createdAt: now.add(const Duration(hours: 1, seconds: 2)),
            ),
          ],
        );

        // 一次调用写入两个会话
        executeSaveConversations(db, _jsonifyMany([convA, convB]));

        // 验证 conversations 表中两行均存在
        final convRows = db.select(
          "SELECT id, title FROM conversations ORDER BY id;",
        );
        expect(convRows.length, equals(2));
        expect(convRows[0]['id'], equals('conv-a'));
        expect(convRows[0]['title'], equals('会话 A'));
        expect(convRows[1]['id'], equals('conv-b'));
        expect(convRows[1]['title'], equals('会话 B'));

        // 验证 conv-a 的消息
        final msgsA = db
            .select("SELECT id, content FROM messages WHERE conversation_id = 'conv-a' ORDER BY node_index;");
        expect(msgsA.length, equals(2));
        expect(msgsA[0]['content'], equals('Message A1'));
        expect(msgsA[1]['content'], equals('Reply A1'));

        // 验证 conv-b 的消息
        final msgsB = db
            .select("SELECT id, content FROM messages WHERE conversation_id = 'conv-b' ORDER BY node_index;");
        expect(msgsB.length, equals(3));
        expect(msgsB[0]['content'], equals('Message B1'));
        expect(msgsB[1]['content'], equals('Reply B1'));
        expect(msgsB[2]['content'], equals('Message B2'));
      } finally {
        db.close();
      }
    });
  });
}
