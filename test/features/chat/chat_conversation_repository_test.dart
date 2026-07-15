import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  late AppDatabase database;
  late SqliteChatConversationRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteChatConversationRepository(database);
  });

  tearDown(() => database.close());

  test('sqlite repository saves and restores branched conversations', () async {
    final conversation = ChatConversation(
      id: 'conversation-1',
      title: '分支会话',
      messageNodes: [
        ChatMessage(
          id: 'user-1',
          role: ChatMessageRole.user,
          content: '当前用户分支',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 4, 27, 10),
          userMessageSegments: const [
            UserMessageSegment(
              text: '当前',
              kind: UserMessageSegmentKind.template,
            ),
            UserMessageSegment(text: '用户分支', kind: UserMessageSegmentKind.body),
          ],
        ),
        ChatMessage(
          id: 'assistant-1',
          role: ChatMessageRole.assistant,
          content: '旧助手分支',
          parentId: 'user-1',
          createdAt: DateTime(2026, 4, 27, 10, 1),
        ),
        ChatMessage(
          id: 'assistant-2',
          role: ChatMessageRole.assistant,
          content: '当前助手分支',
          parentId: 'user-1',
          reasoningContent: '保留思考内容',
          createdAt: DateTime(2026, 4, 27, 10, 2),
        ),
      ],
      excludedMessageIds: const ['assistant-2'],
      selectedChildByParentId: const {
        rootConversationParentId: 'user-1',
        'user-1': 'assistant-2',
      },
      createdAt: DateTime(2026, 4, 27, 10),
      updatedAt: DateTime(2026, 4, 27, 10, 2),
      selectedModelId: 'model-1',
      selectedCheckpointId: 'checkpoint-1',
      selectedPresetPromptId: 'prompt-1',
      checkpoints: [
        ChatCheckpoint(
          id: 'checkpoint-1',
          title: '检查点 1',
          content: '总结当前分支的重要上下文。',
          createdAt: DateTime(2026, 4, 27, 10, 1),
          coveredUntilMessageId: 'assistant-2',
          sourceMemoryPromptName: '研发总结',
        ),
      ],
      reasoningEnabled: true,
      reasoningEffort: ReasoningEffort.high,
    );

    await repository.saveConversations([conversation]);
    final restored = repository.loadAll();

    expect(restored, hasLength(1));
    final restoredConv = restored.single;
    expect(restoredConv.id, conversation.id);
    expect(restoredConv.title, conversation.title);
    expect(restoredConv.createdAt, conversation.createdAt);
    expect(restoredConv.updatedAt, conversation.updatedAt);
    expect(restoredConv.selectedModelId, conversation.selectedModelId);
    expect(restoredConv.selectedCheckpointId, conversation.selectedCheckpointId);
    expect(restoredConv.selectedPresetPromptId,
        conversation.selectedPresetPromptId);
    expect(restoredConv.reasoningEnabled, conversation.reasoningEnabled);
    expect(restoredConv.reasoningEffort, conversation.reasoningEffort);
    expect(restoredConv.selectedChildByParentId,
        equals(conversation.selectedChildByParentId));
    expect(restoredConv.excludedMessageIds, conversation.excludedMessageIds);

    // messageNodes: verify count + IDs, spot-check content fields
    expect(restoredConv.messageNodes, hasLength(3));
    final restoredById = {
      for (final n in restoredConv.messageNodes) n.id: n,
    };
    expect(
      restoredById.keys,
      unorderedEquals(conversation.messageNodes.map((n) => n.id)),
    );
    expect(restoredById['assistant-2']?.reasoningContent, '保留思考内容');
    expect(restoredById['user-1']?.userMessageSegments.length, 2);

    // checkpoints: verify count + key fields
    expect(restoredConv.checkpoints, hasLength(1));
    expect(restoredConv.checkpoints.single.id, 'checkpoint-1');
    expect(restoredConv.checkpoints.single.title, '检查点 1');
    expect(restoredConv.checkpoints.single.content, '总结当前分支的重要上下文。');
  });

  // ── 1. UPSERT idempotency ────────────────────────────────────────────

  test('UPSERT idempotency: re-saving with modified content updates fields without changing count',
      () async {

    // Save initial conversation with 3 messages
    final original = ChatConversation(
      id: 'conv-idempotent',
      title: '更改前标题',
      messageNodes: [
        ChatMessage(
          id: 'msg-1',
          role: ChatMessageRole.user,
          content: '用户消息',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 5, 1, 10),
        ),
        ChatMessage(
          id: 'msg-2',
          role: ChatMessageRole.assistant,
          content: '原始回复',
          parentId: 'msg-1',
          createdAt: DateTime(2026, 5, 1, 10, 1),
        ),
        ChatMessage(
          id: 'msg-3',
          role: ChatMessageRole.assistant,
          content: '另一个回复',
          parentId: 'msg-1',
          createdAt: DateTime(2026, 5, 1, 10, 2),
        ),
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'msg-1',
        'msg-1': 'msg-2',
      },
      createdAt: DateTime(2026, 5, 1, 10),
      updatedAt: DateTime(2026, 5, 1, 10, 2),
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
    );
    await repository.saveConversations([original]);

    // Re-save with same IDs but changed content on msg-2 and new title
    final updated = original.copyWith(
      title: '更改后标题',
      messageNodes: [
        original.messageNodes[0],
        original.messageNodes[1].copyWith(content: '修改后的回复'),
        original.messageNodes[2],
      ],
      updatedAt: DateTime(2026, 5, 1, 11),
    );
    await repository.saveConversations([updated]);

    final all = repository.loadAll();
    expect(all, hasLength(1));
    final restored = all.single;

    // Title updated
    expect(restored.title, '更改后标题');
    // updatedAt updated
    expect(restored.updatedAt, DateTime(2026, 5, 1, 11));
    // Message count unchanged (3 messages total, same IDs)
    expect(restored.messageNodes, hasLength(3));
    // Content of msg-2 was updated by UPSERT
    final msg2 = restored.messageNodes.firstWhere((n) => n.id == 'msg-2');
    expect(msg2.content, '修改后的回复');
    // msg-1 and msg-3 unchanged
    final msg1 = restored.messageNodes.firstWhere((n) => n.id == 'msg-1');
    expect(msg1.content, '用户消息');
    final msg3 = restored.messageNodes.firstWhere((n) => n.id == 'msg-3');
    expect(msg3.content, '另一个回复');
  });

  // ── 2. Ghost row cleanup ─────────────────────────────────────────────

  test('ghost row cleanup: removing a node from messageNodes removes it from DB',
      () async {

    // Save with A → B → C
    final withThree = ChatConversation(
      id: 'conv-ghost',
      title: '三消息会话',
      messageNodes: [
        ChatMessage(
          id: 'a',
          role: ChatMessageRole.user,
          content: 'A',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 5, 2, 10),
        ),
        ChatMessage(
          id: 'b',
          role: ChatMessageRole.assistant,
          content: 'B',
          parentId: 'a',
          createdAt: DateTime(2026, 5, 2, 10, 1),
        ),
        ChatMessage(
          id: 'c',
          role: ChatMessageRole.assistant,
          content: 'C',
          parentId: 'b',
          createdAt: DateTime(2026, 5, 2, 10, 2),
        ),
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'a',
        'a': 'b',
        'b': 'c',
      },
      createdAt: DateTime(2026, 5, 2, 10),
      updatedAt: DateTime(2026, 5, 2, 10, 2),
    );
    await repository.saveConversations([withThree]);

    // Re-save with only A → B (C removed)
    // messageNodes array determines what gets persisted via DELETE + INSERT
    final withoutC = withThree.copyWith(
      messageNodes: [
        withThree.messageNodes[0], // a
        withThree.messageNodes[1], // b
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'a',
        'a': 'b',
      },
      updatedAt: DateTime(2026, 5, 2, 11),
    );
    await repository.saveConversations([withoutC]);

    final all = repository.loadAll();
    expect(all, hasLength(1));
    final restored = all.single;

    // Only 2 messages remain
    expect(restored.messageNodes, hasLength(2));
    expect(restored.messageNodes.map((n) => n.id), ['a', 'b']);

    // Verify via raw SQL that C is truly absent from the database
    final rows = database.connection.select(
      'SELECT id FROM messages WHERE conversation_id = ? ORDER BY node_index',
      ['conv-ghost'],
    );
    expect(rows.map((r) => r['id'] as String), ['a', 'b']);
  });

  // ── 3. Branch selection upsert ───────────────────────────────────────

  test('branch selection upsert: re-saving with different child replaces old selection',
      () async {

    // Save conversation with parent → child1 selection
    final withChild1 = ChatConversation(
      id: 'conv-branch',
      title: '分支选择',
      messageNodes: [
        ChatMessage(
          id: 'u1',
          role: ChatMessageRole.user,
          content: '根消息',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 5, 3, 10),
        ),
        ChatMessage(
          id: 'a1',
          role: ChatMessageRole.assistant,
          content: '分支一',
          parentId: 'u1',
          createdAt: DateTime(2026, 5, 3, 10, 1),
        ),
        ChatMessage(
          id: 'a2',
          role: ChatMessageRole.assistant,
          content: '分支二',
          parentId: 'u1',
          createdAt: DateTime(2026, 5, 3, 10, 2),
        ),
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'u1',
        'u1': 'a1', // initially selects child1
      },
      createdAt: DateTime(2026, 5, 3, 10),
      updatedAt: DateTime(2026, 5, 3, 10, 2),
    );
    await repository.saveConversations([withChild1]);

    // Re-save with {parent: child2} to switch branch selection
    final withChild2 = withChild1.copyWith(
      selectedChildByParentId: const {
        rootConversationParentId: 'u1',
        'u1': 'a2', // switched to child2
      },
      updatedAt: DateTime(2026, 5, 3, 11),
    );
    await repository.saveConversations([withChild2]);

    final all = repository.loadAll();
    expect(all, hasLength(1));
    final restored = all.single;

    // Selection switched from a1 to a2
    expect(restored.selectedChildByParentId['u1'], 'a2');

    // Verify via raw SQL that only one row exists for this parent
    final rows = database.connection.select(
      'SELECT parent_id, child_id FROM conversation_branch_selections WHERE conversation_id = ? AND parent_id = ?',
      ['conv-branch', 'u1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['child_id'] as String, 'a2');
  });

  // ── 4. Empty conversation filter ─────────────────────────────────────

  test('empty conversation filter: saveConversation with no messages, no checkpoints, no title is skipped',
      () async {

    // Build an empty conversation
    final empty = ChatConversation(
      id: 'conv-empty',
      title: null,
      messageNodes: const [],
      createdAt: DateTime(2026, 5, 4, 10),
      updatedAt: DateTime(2026, 5, 4, 10),
    );

    // saveConversation (single, with filter) should skip it
    await repository.saveConversation(empty);

    // loadAll should return nothing
    expect(repository.loadAll(), isEmpty);

    // Direct SQL check: conversations table should be empty
    final rows = database.connection.select(
      'SELECT id FROM conversations WHERE id = ?',
      ['conv-empty'],
    );
    expect(rows, isEmpty);
  });

  // ── 5. Cross-conversation isolation ──────────────────────────────────

  test('cross-conversation isolation: saving convA does not affect convB messages',
      () async {

    // Helper to build a simple conversation
    ChatConversation makeConv(String id, String title, List<String> contents) {
      final nodes = <ChatMessage>[];
      var parent = rootConversationParentId;
      for (var i = 0; i < contents.length; i++) {
        final msgId = '$id-msg-$i';
        nodes.add(ChatMessage(
          id: msgId,
          role: i == 0 ? ChatMessageRole.user : ChatMessageRole.assistant,
          content: contents[i],
          parentId: parent,
          createdAt: DateTime(2026, 5, 5, 10 + i),
        ));
        parent = msgId;
      }

      final selections = <String, String>{};
      parent = rootConversationParentId;
      for (var i = 0; i < contents.length; i++) {
        final msgId = '$id-msg-$i';
        selections[parent] = msgId;
        parent = msgId;
      }

      return ChatConversation(
        id: id,
        title: title,
        messageNodes: List.from(nodes),
        selectedChildByParentId: Map.from(selections),
        createdAt: DateTime(2026, 5, 5, 10),
        updatedAt: DateTime(2026, 5, 5, 10 + contents.length),
      );
    }

    final convA = makeConv('convA', '会话A', ['A-用户', 'A-回复1', 'A-回复2']);
    final convB = makeConv('convB', '会话B', ['B-用户', 'B-回复1', 'B-回复2']);

    // Seed both conversations
    await repository.saveConversations([convA, convB]);

    // Re-save convA with modified content
    final modifiedA = convA.copyWith(
      title: '会话A-修改后',
      messageNodes: [
        convA.messageNodes[0],
        convA.messageNodes[1].copyWith(content: 'A-回复1-修改'),
        convA.messageNodes[2],
      ],
      updatedAt: DateTime(2026, 5, 5, 12),
    );
    await repository.saveConversations([modifiedA]);

    // Reload all
    final all = repository.loadAll();
    expect(all, hasLength(2));

    final restoredA = all.firstWhere((c) => c.id == 'convA');
    final restoredB = all.firstWhere((c) => c.id == 'convB');

    // convA was updated
    expect(restoredA.title, '会话A-修改后');
    expect(restoredA.messageNodes, hasLength(3));
    expect(
      restoredA.messageNodes.firstWhere((n) => n.id == 'convA-msg-1').content,
      'A-回复1-修改',
    );

    // convB messages are completely unchanged
    expect(restoredB.title, '会话B');
    expect(restoredB.messageNodes, hasLength(3));
    expect(
      restoredB.messageNodes.firstWhere((n) => n.id == 'convB-msg-0').content,
      'B-用户',
    );
    expect(
      restoredB.messageNodes.firstWhere((n) => n.id == 'convB-msg-1').content,
      'B-回复1',
    );
    expect(
      restoredB.messageNodes.firstWhere((n) => n.id == 'convB-msg-2').content,
      'B-回复2',
    );
  });

  // ── 6. node_index update ─────────────────────────────────────────────

  test('node_index update: reordering messageNodes updates node_index values',
      () async {

    // Save conversation with messages at indexes 0, 1, 2
    final original = ChatConversation(
      id: 'conv-index',
      title: '索引测试',
      messageNodes: [
        ChatMessage(
          id: 'idx-first',
          role: ChatMessageRole.user,
          content: '第一条',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 5, 6, 10),
        ),
        ChatMessage(
          id: 'idx-second',
          role: ChatMessageRole.assistant,
          content: '第二条',
          parentId: 'idx-first',
          createdAt: DateTime(2026, 5, 6, 10, 1),
        ),
        ChatMessage(
          id: 'idx-third',
          role: ChatMessageRole.assistant,
          content: '第三条',
          parentId: 'idx-second',
          createdAt: DateTime(2026, 5, 6, 10, 2),
        ),
      ],
      selectedChildByParentId: const {
        rootConversationParentId: 'idx-first',
        'idx-first': 'idx-second',
      },
      createdAt: DateTime(2026, 5, 6, 10),
      updatedAt: DateTime(2026, 5, 6, 10, 2),
    );
    await repository.saveConversations([original]);

    // Re-save with reordered messageNodes: second, third, first
    final reordered = original.copyWith(
      messageNodes: [
        original.messageNodes[1], // idx-second → index 0
        original.messageNodes[2], // idx-third  → index 1
        original.messageNodes[0], // idx-first  → index 2
      ],
      // selections must be consistent with new parent-child relationships
      selectedChildByParentId: const {
        rootConversationParentId: 'idx-second',
        'idx-second': 'idx-third',
      },
      updatedAt: DateTime(2026, 5, 6, 11),
    );
    await repository.saveConversations([reordered]);

    // Verify node_index values via raw SQL
    final rows = database.connection.select(
      'SELECT id, node_index FROM messages WHERE conversation_id = ? ORDER BY node_index',
      ['conv-index'],
    );

    expect(rows, hasLength(3));
    // After reorder: idx-second should be at node_index 0, idx-third at 1, idx-first at 2
    expect(rows[0]['id'] as String, 'idx-second');
    expect(rows[0]['node_index'] as int, 0);
    expect(rows[1]['id'] as String, 'idx-third');
    expect(rows[1]['node_index'] as int, 1);
    expect(rows[2]['id'] as String, 'idx-first');
    expect(rows[2]['node_index'] as int, 2);

    // loadConversation should also reflect the new order
    final loaded = repository.loadConversation('conv-index');
    expect(loaded, isNotNull);
    expect(loaded!.messageNodes.map((n) => n.id),
        ['idx-second', 'idx-third', 'idx-first']);
  });

  // ── 7. countHistorySummaries ────────────────────────────────────────

  /// 构造一条带 user 消息 + assistant 对话分支的测试会话。
  ChatConversation buildConv(
    String id, {
    String title = '',
    String userMessageContent = 'hello',
    String assistantContent = 'hi',
    DateTime? updatedAt,
  }) {
    final now = updatedAt ?? DateTime(2026, 6, 1);
    return ChatConversation(
      id: id,
      title: title,
      messageNodes: [
        ChatMessage(
          id: '$id-user',
          role: ChatMessageRole.user,
          content: userMessageContent,
          parentId: rootConversationParentId,
          createdAt: now,
        ),
        ChatMessage(
          id: '$id-assistant',
          role: ChatMessageRole.assistant,
          content: assistantContent,
          parentId: '$id-user',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
      ],
      selectedChildByParentId: {
        rootConversationParentId: '$id-user',
        '$id-user': '$id-assistant',
      },
      createdAt: now,
      updatedAt: now.add(const Duration(minutes: 1)),
    );
  }

  test('countHistorySummaries returns 0 on empty db', () {

    expect(repository.countHistorySummaries(), 0);
    expect(repository.countHistorySummaries(keyword: ''), 0);
    expect(repository.countHistorySummaries(keyword: '不存在的词'), 0);
  });

  test('countHistorySummaries counts all conversations when keyword empty',
      () async {
    await repository.saveConversations([
      buildConv('a'),
      buildConv('b'),
      buildConv('c'),
    ]);

    expect(repository.countHistorySummaries(), 3);
  });

  test('countHistorySummaries matches title keyword case-insensitively',
      () async {
    await repository.saveConversations([
      buildConv('a', title: 'Rust 重构计划'),
      buildConv('b', title: 'Flutter 路线图'),
      buildConv('c', title: '项目复盘'),
    ]);

    expect(repository.countHistorySummaries(keyword: 'rust'), 1);
    expect(repository.countHistorySummaries(keyword: 'FLUTTER'), 1);
    expect(repository.countHistorySummaries(keyword: '计划'), 1);
    expect(repository.countHistorySummaries(keyword: '不存在的标题'), 0);
  });

  test('countHistorySummaries matches user message content across branches',
      () async {
    await repository.saveConversations([
      buildConv('a', userMessageContent: '帮我整理 Rust 模块边界'),
      buildConv('b', userMessageContent: '请给我一份 Widget 测试清单'),
      buildConv('c', userMessageContent: '请总结本周推进情况'),
    ]);

    expect(repository.countHistorySummaries(keyword: 'rust'), 1);
    expect(repository.countHistorySummaries(keyword: 'widget'), 1);
    expect(repository.countHistorySummaries(keyword: '总结'), 1);
    expect(repository.countHistorySummaries(keyword: '模块边界'), 1);
  });

  test('countHistorySummaries escapes LIKE wildcards (% and _)', () async {
    await repository.saveConversations([
      buildConv('pct', title: '进度 50%'),
      buildConv('us', title: '评分_优秀'),
      buildConv('a', title: '正常标题'),
    ]);

    // '50%' 含通配符%，ESCAPE 子句应被当作普通 '%' 字符匹配。
    expect(repository.countHistorySummaries(keyword: '50%'), 1);

    // '评分_优秀' 精确匹配——下划线被转义，不作为 LIKE 通配符
    expect(repository.countHistorySummaries(keyword: '评分_优秀'), 1);

    // 若 _ 未被转义，'评分_' 应能模糊匹配；但转义后只精确匹配原文。
    // 原文是 '评分_优秀'，三个字符依次是 评分_优秀。
    // 搜索 '评分'（不含下划线）仍然通过前缀匹配命中 '评分_优秀'。
    expect(repository.countHistorySummaries(keyword: '评分'), 1);
  });

  test(
      'countHistorySummaries excludes conversations without messages/checkpoints',
      () async {

    // 带消息的会话 -> 计入
    await repository.saveConversations([buildConv('with-msg')]);

    // 无消息、无 checkpoint、空 title 的会话 -> 被 saveConversation 跳过
    // （skip rule），不能直接用 saveConversation 写入；改用 raw insert。
    database.connection.execute(
      'INSERT INTO conversations (id, title, created_at, updated_at, '
      'reasoning_enabled, reasoning_effort, excluded_message_ids_json, '
      'auto_retry_enabled) '
      'VALUES (?, ?, ?, ?, 0, \'medium\', \'[]\', 0)',
      ['ghost', null, DateTime(2026, 1, 1).toIso8601String(), DateTime(2026, 1, 1).toIso8601String()],
    );

    expect(repository.countHistorySummaries(), 1);
    expect(
      repository.countHistorySummaries(keyword: 'ghost'),
      0,
    );
  });

  test(
      'countHistorySummaries result equals loadHistorySummaries pagination sum',
      () async {
    final convs = List.generate(7, (i) => buildConv('c$i'));
    await repository.saveConversations(convs);

    expect(repository.countHistorySummaries(), 7);

    // limit=3 翻页，应该得到 7 条的总和
    var fetched = 0;
    const pageSize = 3;
    for (var offset = 0; offset < 7; offset += pageSize) {
      final page = repository.loadHistorySummaries(limit: pageSize, offset: offset);
      fetched += page.length;
    }
    expect(fetched, repository.countHistorySummaries());
  });
}
