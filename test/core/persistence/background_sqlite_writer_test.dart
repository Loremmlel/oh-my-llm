import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
    late AppDatabase _appDb;
    late sqlite.Database _db;
    late DateTime _now;

    setUp(() {
      _appDb = AppDatabase.inMemory();
      addTearDown(_appDb.close);
      _db = _appDb.connection;
      _now = DateTime.now();
    });

    // ────────────────────────────────────────────
    // 1. UPSERT 幂等性：相同 ID 消息更新不重复
    // ────────────────────────────────────────────
    test('UPSERT idempotency: same ID message updated not duplicated', () {
      final conv = _buildConversation(
        id: 'conv-1',
        title: '测试对话',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'msg-1',
            role: ChatMessageRole.user,
            content: '你好',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'msg-2',
            role: ChatMessageRole.assistant,
            content: '你好！有什么可以帮助你的？',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      // 第一次写入
      executeSaveConversations(_db, _jsonify(conv));

      final modifiedConv = _buildConversation(
        id: 'conv-1',
        title: '测试对话',
        createdAt: _now,
        updatedAt: _now.add(const Duration(minutes: 1)),
        messages: [
          _buildMessage(
            id: 'msg-1',
            role: ChatMessageRole.user,
            content: '你好',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'msg-2',
            role: ChatMessageRole.assistant,
            content: '你好主人喵~',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(modifiedConv));

      final rowCount = _db
          .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-1';")
          .single['cnt'] as int;
      expect(rowCount, equals(2));

      final updatedMsg = _db
          .select("SELECT content FROM messages WHERE id = 'msg-2';")
          .single;
      expect(updatedMsg['content'], equals('你好主人喵~'));

      final convCount = _db
          .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-1';")
          .single['cnt'] as int;
      expect(convCount, equals(1));
    });

    // ────────────────────────────────────────────
    // 2. Ghost row cleanup：消息减少时旧行被清理（含 branch_selections）
    // ────────────────────────────────────────────
    test('Ghost row cleanup: removed message gone after re-save', () {
      final conv = _buildConversation(
        id: 'conv-1',
        title: '三消息对话',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'msg-a',
            role: ChatMessageRole.user,
            content: 'Hello',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'msg-b',
            role: ChatMessageRole.assistant,
            content: 'Hi!',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
          _buildMessage(
            id: 'msg-c',
            role: ChatMessageRole.user,
            content: 'How are you?',
            createdAt: _now.add(const Duration(seconds: 2)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));
      expect(
        _db
            .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-1';")
            .single['cnt'],
        equals(3),
      );

      final slimConv = _buildConversation(
        id: 'conv-1',
        title: '两消息对话',
        createdAt: _now,
        updatedAt: _now.add(const Duration(minutes: 1)),
        messages: [
          _buildMessage(
            id: 'msg-a',
            role: ChatMessageRole.user,
            content: 'Hello',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'msg-b',
            role: ChatMessageRole.assistant,
            content: 'Hi!',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(slimConv));

      final remaining = _db
          .select("SELECT id FROM messages WHERE conversation_id = 'conv-1' ORDER BY node_index;");
      expect(remaining.length, equals(2));
      expect(remaining[0]['id'], equals('msg-a'));
      expect(remaining[1]['id'], equals('msg-b'));

      final ghost = _db
          .select("SELECT COUNT(*) AS cnt FROM messages WHERE id = 'msg-c';")
          .single['cnt'] as int;
      expect(ghost, equals(0));

      final branchCount = _db
          .select("SELECT COUNT(*) AS cnt FROM conversation_branch_selections WHERE conversation_id = 'conv-1';")
          .single['cnt'] as int;
      expect(branchCount, equals(2));
    });

    // ────────────────────────────────────────────
    // 3. node_index 首次写入即为 0,1,2
    // ────────────────────────────────────────────
    test('node_index sequential on first write', () {
      final conv = _buildConversation(
        id: 'conv-1',
        title: '索引测试',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'm1',
            role: ChatMessageRole.user,
            content: 'First',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'm2',
            role: ChatMessageRole.assistant,
            content: 'Second',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
          _buildMessage(
            id: 'm3',
            role: ChatMessageRole.user,
            content: 'Third',
            createdAt: _now.add(const Duration(seconds: 2)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));

      final rows = _db
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
      final conv = _buildConversation(
        id: 'conv-1',
        title: '索引测试',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'm1',
            role: ChatMessageRole.user,
            content: 'First',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'm2',
            role: ChatMessageRole.assistant,
            content: 'Second',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
          _buildMessage(
            id: 'm3',
            role: ChatMessageRole.user,
            content: 'Third',
            createdAt: _now.add(const Duration(seconds: 2)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));

      final modifiedConv = _buildConversation(
        id: 'conv-1',
        title: '索引测试',
        createdAt: _now,
        updatedAt: _now.add(const Duration(minutes: 1)),
        messages: [
          _buildMessage(
            id: 'm1',
            role: ChatMessageRole.user,
            content: 'First',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'm2',
            role: ChatMessageRole.assistant,
            content: 'Second (edited)',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
          _buildMessage(
            id: 'm3',
            role: ChatMessageRole.user,
            content: 'Third',
            createdAt: _now.add(const Duration(seconds: 2)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(modifiedConv));

      final rows = _db
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
      final conv = _buildConversation(
        id: 'conv-tx',
        title: '原子性测试',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'tx-msg-1',
            role: ChatMessageRole.user,
            content: 'Atomic test',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'tx-msg-2',
            role: ChatMessageRole.assistant,
            content: 'Response',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));

      final convRow = _db
          .select("SELECT * FROM conversations WHERE id = 'conv-tx';");
      expect(convRow.length, equals(1));
      expect(convRow.single['title'], equals('原子性测试'));

      final msgRows = _db
          .select("SELECT * FROM messages WHERE conversation_id = 'conv-tx';");
      expect(msgRows.length, equals(2));
      expect(msgRows[0]['id'], equals('tx-msg-1'));
      expect(msgRows[1]['id'], equals('tx-msg-2'));

      executeSaveConversations(_db, _jsonify(conv));
      final convCount = _db
          .select("SELECT COUNT(*) AS cnt FROM conversations WHERE id = 'conv-tx';")
          .single['cnt'] as int;
      expect(convCount, equals(1));
      final msgCount = _db
          .select("SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = 'conv-tx';")
          .single['cnt'] as int;
      expect(msgCount, equals(2));
    });

    // ────────────────────────────────────────────
    // 6. 事务回滚：在已关闭连接上写入失败时不残留半截行
    // ────────────────────────────────────────────
    test('Transaction rollback leaves no partial rows on failed write', () {
      final tmpDir = Directory.systemTemp.createTempSync('rollback-test-');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });
      final dbPath = '${tmpDir.path}${Platform.pathSeparator}rollback.sqlite';

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
      final convA = _buildConversation(
        id: 'conv-a',
        title: '会话 A',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'a-msg-1',
            role: ChatMessageRole.user,
            content: 'Message A1',
            createdAt: _now,
          ),
          _buildMessage(
            id: 'a-msg-2',
            role: ChatMessageRole.assistant,
            content: 'Reply A1',
            createdAt: _now.add(const Duration(seconds: 1)),
          ),
        ],
      );

      final convB = _buildConversation(
        id: 'conv-b',
        title: '会话 B',
        createdAt: _now.add(const Duration(hours: 1)),
        updatedAt: _now.add(const Duration(hours: 1)),
        messages: [
          _buildMessage(
            id: 'b-msg-1',
            role: ChatMessageRole.user,
            content: 'Message B1',
            createdAt: _now.add(const Duration(hours: 1)),
          ),
          _buildMessage(
            id: 'b-msg-2',
            role: ChatMessageRole.assistant,
            content: 'Reply B1',
            createdAt: _now.add(const Duration(hours: 1, seconds: 1)),
          ),
          _buildMessage(
            id: 'b-msg-3',
            role: ChatMessageRole.user,
            content: 'Message B2',
            createdAt: _now.add(const Duration(hours: 1, seconds: 2)),
          ),
        ],
      );

      executeSaveConversations(_db, _jsonifyMany([convA, convB]));

      final convRows = _db.select(
        "SELECT id, title FROM conversations ORDER BY id;",
      );
      expect(convRows.length, equals(2));
      expect(convRows[0]['id'], equals('conv-a'));
      expect(convRows[0]['title'], equals('会话 A'));
      expect(convRows[1]['id'], equals('conv-b'));
      expect(convRows[1]['title'], equals('会话 B'));

      final msgsA = _db
          .select("SELECT id, content FROM messages WHERE conversation_id = 'conv-a' ORDER BY node_index;");
      expect(msgsA.length, equals(2));
      expect(msgsA[0]['content'], equals('Message A1'));
      expect(msgsA[1]['content'], equals('Reply A1'));

      final msgsB = _db
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
      final conv = _buildConversation(
        id: 'conv-cp',
        title: '检查点测试',
        createdAt: _now,
        updatedAt: _now,
        messages: [
          _buildMessage(
            id: 'cp-msg-1',
            role: ChatMessageRole.user,
            content: 'hi',
            createdAt: _now,
          ),
        ],
        checkpoints: [
          ChatCheckpoint(
            id: 'cp-1',
            title: '检查点 1',
            content: '摘要 1',
            createdAt: _now,
            parentCheckpointId: null,
            coveredUntilMessageId: 'cp-msg-1',
            sourceMemoryPromptName: '记忆源 A',
          ),
          ChatCheckpoint(
            id: 'cp-2',
            title: '检查点 2',
            content: '摘要 2',
            createdAt: _now.add(const Duration(minutes: 1)),
            parentCheckpointId: 'cp-1',
            coveredUntilMessageId: null,
            sourceMemoryPromptName: '',
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));

      final cpRows = _db.select(
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

      final slimConv = _buildConversation(
        id: 'conv-cp',
        title: '检查点测试',
        createdAt: _now,
        updatedAt: _now.add(const Duration(minutes: 2)),
        messages: [
          _buildMessage(
            id: 'cp-msg-1',
            role: ChatMessageRole.user,
            content: 'hi',
            createdAt: _now,
          ),
        ],
        checkpoints: const [],
      );
      executeSaveConversations(_db, _jsonify(slimConv));

      final cpCount = _db
          .select("SELECT COUNT(*) AS cnt FROM conversation_checkpoints WHERE conversation_id = 'conv-cp';")
          .single['cnt'] as int;
      expect(cpCount, equals(0));
    });

    // ────────────────────────────────────────────
    // 9. 空会话列表为 no-op
    // ────────────────────────────────────────────
    test('empty conversations list is a no-op', () {
      expect(
        _db.select("SELECT COUNT(*) AS cnt FROM conversations;").single['cnt'],
        equals(0),
      );

      executeSaveConversations(_db, const []);

      expect(
        _db.select("SELECT COUNT(*) AS cnt FROM conversations;").single['cnt'],
        equals(0),
      );
      expect(
        _db.select("SELECT COUNT(*) AS cnt FROM messages;").single['cnt'],
        equals(0),
      );
    });

    // ────────────────────────────────────────────
    // 10. 全字段非默认值往返持久化
    // ────────────────────────────────────────────
    test('conversation fields round-trip persistence', () {
      final conv = _buildConversation(
        id: 'conv-full',
        title: '全字段',
        createdAt: _now,
        updatedAt: _now,
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
            createdAt: _now,
          ),
        ],
      );

      executeSaveConversations(_db, _jsonify(conv));

      final row = _db
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
