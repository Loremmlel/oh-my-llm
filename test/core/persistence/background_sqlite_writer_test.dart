import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/background_sqlite_writer.dart'
    show executeSaveConversations;
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

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
  List<ChatCheckpoint> checkpoints = const [],
}) {
  final now = DateTime.now();
  String parentId = rootConversationParentId;
  final nodes = messages
      .map((message) {
        final next = message.copyWith(parentId: parentId);
        parentId = next.id;
        return next;
      })
      .toList(growable: false);
  final selections = <String, String>{};
  var selParentId = rootConversationParentId;
  for (final node in nodes) {
    selections[selParentId] = node.id;
    selParentId = node.id;
  }
  return ChatConversation(
    id: id,
    title: title,
    messageNodes: nodes,
    selectedChildByParentId: selections,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    selectedModelId: selectedModelId,
    selectedCheckpointId: selectedCheckpointId,
    selectedPresetPromptId: selectedPresetPromptId,
    reasoningEnabled: reasoningEnabled,
    reasoningEffort: reasoningEffort,
    autoRetryEnabled: autoRetryEnabled,
    excludedMessageIds: excludedMessageIds,
    checkpoints: checkpoints,
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
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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
    });

    // ────────────────────────────────────────────
    // 2. Ghost row cleanup：消息减少时旧行被清理（含 branch_selections）
    // ────────────────────────────────────────────
    test('Ghost row cleanup: removed message gone after re-save', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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

      // 验证 branch_selections 中与 msg-c 相关的行已被清理
      final branchCount = db
          .select("SELECT COUNT(*) AS cnt FROM conversation_branch_selections WHERE conversation_id = 'conv-1';")
          .single['cnt'] as int;
      expect(branchCount, equals(2));
    });

    // ────────────────────────────────────────────
    // 3. node_index 首次写入即为 0,1,2
    // ────────────────────────────────────────────
    test('node_index sequential on first write', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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

      final rows = db
          .select("SELECT id, node_index FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
      expect(rows[0]['id'], equals('m1'));
      expect(rows[0]['node_index'], equals(0));
      expect(rows[1]['id'], equals('m2'));
      expect(rows[1]['node_index'], equals(1));
      expect(rows[2]['id'], equals('m3'));
      expect(rows[2]['node_index'], equals(2));
    });

    // ────────────────────────────────────────────
    // 4. node_index 在内容编辑后重存仍保持正确
    // ────────────────────────────────────────────
    test('node_index preserved after content edit re-save', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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

      // 验证 node_index 仍为正确的 0, 1, 2 且内容已更新
      final rows = db
          .select("SELECT id, node_index, content FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
      expect(rows.length, equals(3));
      expect(rows[0]['node_index'], equals(0));
      expect(rows[1]['node_index'], equals(1));
      expect(rows[1]['content'], equals('Second (edited)'));
      expect(rows[2]['node_index'], equals(2));
    });

    // ────────────────────────────────────────────
    // 5. 重复保存保持单行：UPSERT 不产生重复 conversation 行
    // ────────────────────────────────────────────
    test('Re-saving same conversation keeps single conversation row', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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
    });

    // ────────────────────────────────────────────
    // 6. 事务回滚：在已关闭连接上写入失败时不残留半截行
    // ────────────────────────────────────────────
    test('Transaction rollback leaves no partial rows on failed write', () {
      // 用文件数据库以便关闭后重新打开验证
      final tmpDir = Directory.systemTemp.createTempSync('rollback-test-');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });
      final dbPath = '${tmpDir.path}${Platform.pathSeparator}rollback.sqlite';

      // 先正常写入一条基线数据
      final appDb = AppDatabase.forPath(dbPath);
      addTearDown(appDb.close);
      final db = appDb.connection;

      final now = DateTime.now();
      final baselineConv = _buildConversation(
        id: 'conv-baseline',
        title: '基线',
        createdAt: now,
        updatedAt: now,
        messages: [
          _buildMessage(
            id: 'base-msg-1',
            role: ChatMessageRole.user,
            content: 'baseline',
            createdAt: now,
          ),
        ],
      );
      executeSaveConversations(db, _jsonify(baselineConv));

      // 构造第二个会话，用于触发失败的写入
      final failingConv = _buildConversation(
        id: 'conv-failing',
        title: '将失败',
        createdAt: now,
        updatedAt: now,
        messages: [
          _buildMessage(
            id: 'fail-msg-1',
            role: ChatMessageRole.user,
            content: 'will fail',
            createdAt: now,
          ),
        ],
      );

      // 关闭连接后调用 executeSaveConversations，应抛异常（事务被回滚）
      appDb.close();
      expect(
        () => executeSaveConversations(db, _jsonify(failingConv)),
        throwsA(isA<Object>()),
      );

      // 重新打开同一文件，验证失败的会话未残留任何行
      final reopened = AppDatabase.forPath(dbPath);
      addTearDown(reopened.close);
      final failingCount = reopened.connection
          .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-failing';")
          .single['cnt'] as int;
      expect(failingCount, equals(0));
      final failingMsgCount = reopened.connection
          .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-failing';")
          .single['cnt'] as int;
      expect(failingMsgCount, equals(0));

      // 基线数据仍完好
      final baselineCount = reopened.connection
          .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-baseline';")
          .single['cnt'] as int;
      expect(baselineCount, equals(1));
    });

    // ────────────────────────────────────────────
    // 7. 多会话写入：两个会话同时持久化
    // ────────────────────────────────────────────
    test('Multi-conversation write: both persisted correctly', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

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
    });

    // ────────────────────────────────────────────
    // 8. checkpoints 持久化与重存时清理
    // ────────────────────────────────────────────
    test('checkpoints are persisted and cleaned up on re-save', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

      final now = DateTime.now();
      final conv = _buildConversation(
        id: 'conv-cp',
        title: '检查点测试',
        createdAt: now,
        updatedAt: now,
        messages: [
          _buildMessage(
            id: 'cp-msg-1',
            role: ChatMessageRole.user,
            content: 'hi',
            createdAt: now,
          ),
        ],
        checkpoints: [
          ChatCheckpoint(
            id: 'cp-1',
            title: '检查点 1',
            content: '摘要 1',
            createdAt: now,
            parentCheckpointId: null,
            coveredUntilMessageId: 'cp-msg-1',
            sourceMemoryPromptName: '记忆源 A',
          ),
          ChatCheckpoint(
            id: 'cp-2',
            title: '检查点 2',
            content: '摘要 2',
            createdAt: now.add(const Duration(minutes: 1)),
            parentCheckpointId: 'cp-1',
            coveredUntilMessageId: null,
            sourceMemoryPromptName: '',
          ),
        ],
      );

      executeSaveConversations(db, _jsonify(conv));

      // 验证两个 checkpoint 已写入，且字段往返正确
      final cpRows = db.select(
        "SELECT id, title, content, parent_checkpoint_id, covered_until_message_id, source_memory_prompt_name FROM conversation_checkpoints WHERE conversation_id = 'conv-cp' ORDER BY id;",
      );
      expect(cpRows.length, equals(2));
      expect(cpRows[0]['id'], equals('cp-1'));
      expect(cpRows[0]['title'], equals('检查点 1'));
      expect(cpRows[0]['content'], equals('摘要 1'));
      expect(cpRows[0]['parent_checkpoint_id'], isNull);
      expect(cpRows[0]['covered_until_message_id'], equals('cp-msg-1'));
      expect(cpRows[0]['source_memory_prompt_name'], equals('记忆源 A'));
      expect(cpRows[1]['id'], equals('cp-2'));
      expect(cpRows[1]['parent_checkpoint_id'], equals('cp-1'));
      expect(cpRows[1]['source_memory_prompt_name'], equals(''));

      // 重新保存不带 checkpoint 的会话，验证旧 checkpoint 被清理
      final slimConv = _buildConversation(
        id: 'conv-cp',
        title: '检查点测试',
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 2)),
        messages: [
          _buildMessage(
            id: 'cp-msg-1',
            role: ChatMessageRole.user,
            content: 'hi',
            createdAt: now,
          ),
        ],
        checkpoints: const [],
      );
      executeSaveConversations(db, _jsonify(slimConv));

      final cpCount = db
          .select("SELECT COUNT(*) AS cnt FROM conversation_checkpoints WHERE conversation_id = 'conv-cp';")
          .single['cnt'] as int;
      expect(cpCount, equals(0));
    });

    // ────────────────────────────────────────────
    // 9. 空会话列表为 no-op
    // ────────────────────────────────────────────
    test('empty conversations list is a no-op', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

      // 表初始为空
      expect(
        db.select("SELECT COUNT(*) AS cnt FROM conversations;").single['cnt'],
        equals(0),
      );

      // 传入空列表不应抛异常，也不应写入任何行
      executeSaveConversations(db, const []);

      expect(
        db.select("SELECT COUNT(*) AS cnt FROM conversations;").single['cnt'],
        equals(0),
      );
      expect(
        db.select("SELECT COUNT(*) AS cnt FROM messages;").single['cnt'],
        equals(0),
      );
    });

    // ────────────────────────────────────────────
    // 10. 全字段非默认值往返持久化
    // ────────────────────────────────────────────
    test('conversation fields round-trip persistence', () {
      final appDb = AppDatabase.inMemory();
      addTearDown(appDb.close);
      final db = appDb.connection;

      final now = DateTime.now();
      final conv = _buildConversation(
        id: 'conv-full',
        title: '全字段',
        createdAt: now,
        updatedAt: now,
        selectedModelId: 'model-x',
        selectedCheckpointId: 'cp-x',
        selectedPresetPromptId: 'pp-x',
        reasoningEnabled: true,
        reasoningEffort: ReasoningEffort.high,
        autoRetryEnabled: true,
        excludedMessageIds: const ['excluded-1', 'excluded-2'],
        messages: [
          _buildMessage(
            id: 'full-msg-1',
            role: ChatMessageRole.user,
            content: 'full',
            createdAt: now,
          ),
        ],
      );

      executeSaveConversations(db, _jsonify(conv));

      final row = db
          .select("SELECT * FROM conversations WHERE id = 'conv-full';")
          .single;
      expect(row['selected_model_id'], equals('model-x'));
      expect(row['selected_checkpoint_id'], equals('cp-x'));
      expect(row['selected_preset_prompt_id'], equals('pp-x'));
      expect(row['reasoning_enabled'], equals(1));
      expect(row['reasoning_effort'], equals(ReasoningEffort.high.apiValue));
      expect(row['auto_retry_enabled'], equals(1));
      expect(
        row['excluded_message_ids_json'],
        equals('["excluded-1","excluded-2"]'),
      );
    });
  });
}
