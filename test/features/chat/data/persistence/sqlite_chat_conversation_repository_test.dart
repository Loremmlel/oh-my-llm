import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
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

  test('保存并恢复会话的全部消息分支与检查点', () async {
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
          templatePromptId: 'template-1',
          templateVariableValues: const {'language': 'Dart'},
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
          assistantModelDisplayName: '测试模型',
          appliedCheckpointTitle: '检查点 1',
          createdAt: DateTime(2026, 4, 27, 10, 2),
          finishReason: 'stop',
          tokenUsage: const LlmUsage(
            inputTokens: 4000,
            outputTokens: 900,
            cachedInputTokens: 1500,
            cacheWriteInputTokens: 800,
          ),
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
      autoRetryEnabled: true,
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
    expect(
      restoredConv.selectedCheckpointId,
      conversation.selectedCheckpointId,
    );
    expect(
      restoredConv.selectedPresetPromptId,
      conversation.selectedPresetPromptId,
    );
    expect(restoredConv.reasoningEnabled, conversation.reasoningEnabled);
    expect(restoredConv.reasoningEffort, conversation.reasoningEffort);
    expect(restoredConv.autoRetryEnabled, isTrue);
    expect(
      restoredConv.selectedChildByParentId,
      equals(conversation.selectedChildByParentId),
    );
    expect(restoredConv.excludedMessageIds, conversation.excludedMessageIds);

    expect(restoredConv.messageNodes, hasLength(3));
    final restoredById = {for (final n in restoredConv.messageNodes) n.id: n};
    expect(
      restoredById.keys,
      unorderedEquals(conversation.messageNodes.map((n) => n.id)),
    );
    expect(restoredById['assistant-2']?.reasoningContent, '保留思考内容');
    expect(restoredById['assistant-2']?.assistantModelDisplayName, '测试模型');
    expect(restoredById['assistant-2']?.appliedCheckpointTitle, '检查点 1');
    expect(restoredById['assistant-2']?.finishReason, 'stop');
    expect(
      restoredById['assistant-2']?.tokenUsage,
      conversation.messageNodes.last.tokenUsage,
    );
    expect(restoredById['user-1']?.userMessageSegments.length, 2);
    expect(restoredById['user-1']?.templatePromptId, 'template-1');
    expect(restoredById['user-1']?.templateVariableValues, {
      'language': 'Dart',
    });

    expect(restoredConv.checkpoints, hasLength(1));
    expect(restoredConv.checkpoints.single.id, 'checkpoint-1');
    expect(restoredConv.checkpoints.single.title, '检查点 1');
    expect(restoredConv.checkpoints.single.content, '总结当前分支的重要上下文。');
  });

  // ── 1. UPSERT idempotency ────────────────────────────────────────────

  test('重复保存相同 ID 更新标题与正文，保留未修改消息且不增加行数', () async {
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

    expect(restored.title, '更改后标题');
    expect(restored.updatedAt, DateTime(2026, 5, 1, 11));
    expect(restored.messageNodes, hasLength(3));
    final msg2 = restored.messageNodes.firstWhere((n) => n.id == 'msg-2');
    expect(msg2.content, '修改后的回复');
    final msg1 = restored.messageNodes.firstWhere((n) => n.id == 'msg-1');
    expect(msg1.content, '用户消息');
    final msg3 = restored.messageNodes.firstWhere((n) => n.id == 'msg-3');
    expect(msg3.content, '另一个回复');
  });

  // ── 2. Ghost row cleanup ─────────────────────────────────────────────

  test('删除消息节点后再次保存，数据库不残留旧节点', () async {
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
          tokenUsage: const LlmUsage(inputTokens: 100, cachedInputTokens: 50),
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

    final withoutC = withThree.copyWith(
      messageNodes: [
        withThree.messageNodes[0], // a
        withThree.messageNodes[1], // b
      ],
      selectedChildByParentId: const {rootConversationParentId: 'a', 'a': 'b'},
      updatedAt: DateTime(2026, 5, 2, 11),
    );
    await repository.saveConversations([withoutC]);

    final all = repository.loadAll();
    expect(all, hasLength(1));
    final restored = all.single;

    expect(restored.messageNodes, hasLength(2));
    expect(restored.messageNodes.map((n) => n.id), ['a', 'b']);

    final rows = database.connection.select(
      'SELECT id FROM messages WHERE conversation_id = ? ORDER BY node_index',
      ['conv-ghost'],
    );
    expect(rows.map((r) => r['id'] as String), ['a', 'b']);
  });

  test('再次保存会话时删除新状态已移除的检查点', () async {
    final original = ChatConversation(
      id: 'conv-checkpoint-cleanup',
      messageNodes: [
        ChatMessage(
          id: 'user',
          role: ChatMessageRole.user,
          content: '保留消息',
          parentId: rootConversationParentId,
          createdAt: DateTime(2026, 5, 2, 10),
        ),
      ],
      checkpoints: [
        ChatCheckpoint(
          id: 'checkpoint',
          title: '待移除检查点',
          content: '旧摘要',
          createdAt: DateTime(2026, 5, 2, 10),
        ),
      ],
      createdAt: DateTime(2026, 5, 2, 10),
      updatedAt: DateTime(2026, 5, 2, 10),
    );
    await repository.saveConversations([original]);

    await repository.saveConversations([
      original.copyWith(
        checkpoints: const [],
        updatedAt: DateTime(2026, 5, 2, 11),
      ),
    ]);

    expect(repository.loadConversation(original.id)?.checkpoints, isEmpty);
  });

  // ── 3. Branch selection upsert ───────────────────────────────────────

  test('再次保存分支选择替换旧选中项且同一父节点只有一条选择记录', () async {
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

    expect(restored.selectedChildByParentId['u1'], 'a2');

    final rows = database.connection.select(
      'SELECT parent_id, child_id FROM conversation_branch_selections WHERE conversation_id = ? AND parent_id = ?',
      ['conv-branch', 'u1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['child_id'] as String, 'a2');
  });

  // ── 4. Empty conversation filter ─────────────────────────────────────

  test('没有标题、消息和检查点的空白会话不写入数据库', () async {
    final empty = ChatConversation(
      id: 'conv-empty',
      title: null,
      messageNodes: const [],
      createdAt: DateTime(2026, 5, 4, 10),
      updatedAt: DateTime(2026, 5, 4, 10),
    );

    await repository.saveConversation(empty);

    expect(repository.loadAll(), isEmpty);

    final rows = database.connection.select(
      'SELECT id FROM conversations WHERE id = ?',
      ['conv-empty'],
    );
    expect(rows, isEmpty);
  });

  // ── 5. Cross-conversation isolation ──────────────────────────────────

  test('更新一个会话时不修改另一个会话的消息', () async {
    ChatConversation makeConv(String id, String title, List<String> contents) {
      final nodes = <ChatMessage>[];
      var parent = rootConversationParentId;
      for (var i = 0; i < contents.length; i++) {
        final msgId = '$id-msg-$i';
        nodes.add(
          ChatMessage(
            id: msgId,
            role: i == 0 ? ChatMessageRole.user : ChatMessageRole.assistant,
            content: contents[i],
            parentId: parent,
            createdAt: DateTime(2026, 5, 5, 10 + i),
          ),
        );
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

    await repository.saveConversations([convA, convB]);

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

    final all = repository.loadAll();
    expect(all, hasLength(2));

    final restoredA = all.firstWhere((c) => c.id == 'convA');
    final restoredB = all.firstWhere((c) => c.id == 'convB');

    expect(restoredA.title, '会话A-修改后');
    expect(restoredA.messageNodes, hasLength(3));
    expect(
      restoredA.messageNodes.firstWhere((n) => n.id == 'convA-msg-1').content,
      'A-回复1-修改',
    );

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

  test('调整消息顺序后数据库索引和读取顺序一致', () async {
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

    final reordered = original.copyWith(
      messageNodes: [
        original.messageNodes[1], // idx-second → index 0
        original.messageNodes[2], // idx-third  → index 1
        original.messageNodes[0], // idx-first  → index 2
      ],
      // 分支选择必须与重新排列后的父子关系一致，保证 fixture 仍是合法消息树。
      selectedChildByParentId: const {
        rootConversationParentId: 'idx-second',
        'idx-second': 'idx-third',
      },
      updatedAt: DateTime(2026, 5, 6, 11),
    );
    await repository.saveConversations([reordered]);

    final rows = database.connection.select(
      'SELECT id, node_index FROM messages WHERE conversation_id = ? ORDER BY node_index',
      ['conv-index'],
    );

    expect(rows, hasLength(3));
    expect(rows[0]['id'] as String, 'idx-second');
    expect(rows[0]['node_index'] as int, 0);
    expect(rows[1]['id'] as String, 'idx-third');
    expect(rows[1]['node_index'] as int, 1);
    expect(rows[2]['id'] as String, 'idx-first');
    expect(rows[2]['node_index'] as int, 2);

    final loaded = repository.loadConversation('conv-index');
    expect(loaded, isNotNull);
    expect(loaded!.messageNodes.map((n) => n.id), [
      'idx-second',
      'idx-third',
      'idx-first',
    ]);
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

  test('空数据库的全部和关键字历史计数均为零', () {
    expect(repository.countHistorySummaries(), 0);
    expect(repository.countHistorySummaries(keyword: ''), 0);
    expect(repository.countHistorySummaries(keyword: '不存在的词'), 0);
  });

  test('空关键字统计全部非空会话', () async {
    await repository.saveConversations([
      buildConv('a'),
      buildConv('b'),
      buildConv('c'),
    ]);

    expect(repository.countHistorySummaries(), 3);
  });

  test('历史搜索匹配标题且不区分大小写', () async {
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

  test('历史搜索匹配用户消息，包括未选中的分支', () async {
    final branched = buildConv('a', userMessageContent: '帮我整理 Rust 模块边界');
    await repository.saveConversations([
      branched.copyWith(
        messageNodes: [
          ...branched.messageNodes,
          ChatMessage(
            id: 'hidden-user',
            role: ChatMessageRole.user,
            content: '隐藏分支内容',
            parentId: rootConversationParentId,
            createdAt: DateTime(2026, 6, 2),
          ),
        ],
      ),
      buildConv('b', userMessageContent: '请给我一份 Widget 测试清单'),
      buildConv('c', userMessageContent: '请总结本周推进情况'),
    ]);

    expect(repository.countHistorySummaries(keyword: 'rust'), 1);
    expect(repository.countHistorySummaries(keyword: 'widget'), 1);
    expect(repository.countHistorySummaries(keyword: '总结'), 1);
    expect(repository.countHistorySummaries(keyword: '模块边界'), 1);
    expect(repository.countHistorySummaries(keyword: '隐藏分支'), 1);
  });

  test('历史搜索将百分号和下划线按字面匹配，排除通配诱饵', () async {
    await repository.saveConversations([
      buildConv('pct', title: '进度 50%'),
      buildConv('us', title: '评分_优秀'),
      buildConv('percent-bait', title: '进度 50X'),
      buildConv('underscore-bait', title: '评分A优秀'),
      buildConv('a', title: '正常标题'),
    ]);

    // '50%' 含通配符%，ESCAPE 子句应被当作普通 '%' 字符匹配。
    expect(repository.countHistorySummaries(keyword: '50%'), 1);

    // '评分_优秀' 精确匹配——下划线被转义，不作为 LIKE 通配符
    expect(repository.countHistorySummaries(keyword: '评分_优秀'), 1);

    expect(repository.countHistorySummaries(keyword: '评分'), 2);
  });

  test('历史计数排除没有消息或检查点的会话', () async {
    // 带消息的会话 -> 计入
    await repository.saveConversations([buildConv('with-msg')]);

    // 无消息、无 checkpoint、空 title 的会话 -> 被 saveConversation 跳过
    // （skip rule），不能直接用 saveConversation 写入；改用 raw insert。
    database.connection.execute(
      'INSERT INTO conversations (id, title, created_at, updated_at, '
      'reasoning_enabled, reasoning_effort, excluded_message_ids_json, '
      'auto_retry_enabled) '
      'VALUES (?, ?, ?, ?, 0, \'medium\', \'[]\', 0)',
      [
        'ghost',
        null,
        DateTime(2026, 1, 1).toIso8601String(),
        DateTime(2026, 1, 1).toIso8601String(),
      ],
    );

    expect(repository.countHistorySummaries(), 1);
    expect(repository.countHistorySummaries(keyword: 'ghost'), 0);
  });

  test('历史分页按时间返回全部会话，无遗漏或重复', () async {
    final convs = List.generate(
      7,
      (i) => buildConv('c$i', updatedAt: DateTime(2026, 6, 1, 0, i)),
    );
    await repository.saveConversations(convs);

    expect(repository.countHistorySummaries(), 7);

    // limit=3 翻页，应该得到 7 条的总和
    final fetchedIds = <String>[];
    const pageSize = 3;
    for (var offset = 0; offset < 7; offset += pageSize) {
      final page = repository.loadHistorySummaries(
        limit: pageSize,
        offset: offset,
      );
      fetchedIds.addAll(page.map((item) => item.id));
    }
    expect(fetchedIds, ['c6', 'c5', 'c4', 'c3', 'c2', 'c1', 'c0']);
  });
}
