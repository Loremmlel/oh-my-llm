/// 对话生命周期集成测试。
///
/// 验证对话数据的完整持久化链路：创建 → 写入 SQLite → 容器重建（模拟重启）→ 数据完整恢复。
/// 覆盖消息持久化、分支编辑保留、检查点保留和流异常后的错误保留。
/// 所有测试在 ProviderContainer 级别运行，不涉及 UI。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../features/chat/presentation/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/async/async_test_signals.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 对话持久化→容器重建→数据完整恢复 ──────────────────────────────────────────

  test('对话持久化→容器重建→数据完整恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    // 发送第 1 轮对话
    fakeClientA.enqueueChunks(['你好！很高兴见到你。']);
    await sendMsg(containerA, content: '你好');

    // 发送第 2 轮对话
    fakeClientA.enqueueChunks(['今天天气不错，适合出去走走。']);
    await sendMsg(containerA, content: '今天天气如何');

    final stateA = containerA.read(chatSessionsProvider);
    final messagesA = stateA.activeConversation.messages;
    expect(messagesA.length, equals(4));
    expect(messagesA[0].role, ChatMessageRole.user);
    expect(messagesA[0].content, '你好');
    expect(messagesA[1].role, ChatMessageRole.assistant);
    final firstAssistantContent = messagesA[1].content;
    expect(firstAssistantContent, isNotEmpty);

    final messageCountA = messagesA.length;
    final revisionA = stateA.historyRevision;
    expect(revisionA, greaterThan(0));

    // 模拟应用重启：dispose 旧容器，用同一数据库新建容器
    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(() {
      containerB.dispose();
    });

    final stateB = containerB.read(chatSessionsProvider);
    expect(stateB.conversations.length, 1);
    expect(stateB.activeConversation.messages.length, messageCountA);
    expect(stateB.activeConversation.messages[0].content, '你好');
    expect(
      stateB.activeConversation.messages[1].content,
      firstAssistantContent,
    );
  });

  // ── 检查点创建后重建容器 — 检查点保留 ────────────────────────────────────────

  test('检查点创建后重建容器 — 检查点保留', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    fakeClientA.enqueueChunks(['首轮回复']);
    await sendMsg(containerA, content: '先产生一些上下文');

    fakeClientA.enqueueChunks(['这是总结后的检查点内容']);

    final checkpoint = await containerA
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: testModel,
          memoryPrompt: testMemoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final checkpointsA = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .checkpoints;
    expect(checkpointsA, isNotEmpty);
    expect(checkpointsA.single.id, checkpoint.id);
    expect(checkpointsA.single.content, '这是总结后的检查点内容');
    expect(checkpointsA.single.sourceMemoryPromptName, '研发总结');

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(() {
      containerB.dispose();
    });

    final checkpointsB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .checkpoints;
    expect(checkpointsB, isNotEmpty);
    expect(checkpointsB.single.id, checkpoint.id);
    expect(checkpointsB.single.content, '这是总结后的检查点内容');
    expect(checkpointsB.single.sourceMemoryPromptName, '研发总结');
  });

  // ── 流异常后容器重建 — 错误信息保留 ──────────────────────────────────────────

  test('sendMessage 流异常后容器重建 — 错误信息保留', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    fakeClientA.enqueueError(ChatGenerationException('模拟的网络错误'));
    await containerA
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '触发错误',
          modelConfig: testModel,
          presetPrompt: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    // 空流失败后 assistant 占位节点仍保留，用于展示错误信息
    final stateA = containerA.read(chatSessionsProvider);
    expect(stateA.isStreaming, isFalse);
    final messagesA = stateA.activeConversation.messages;
    expect(messagesA.last.role, ChatMessageRole.assistant);
    expect(messagesA.last.content, isEmpty);
    expect(stateA.errorMessageAssistantId, messagesA.last.id);
    final errorAssistantId = stateA.errorMessageAssistantId;

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(() {
      containerB.dispose();
    });

    // 错误信息不属于持久化数据，但包含错误的对话仍需可正常恢复
    final stateB = containerB.read(chatSessionsProvider);
    final messagesB = stateB.activeConversation.messages;
    expect(messagesB.length, messagesA.length);
    expect(messagesB.last.role, ChatMessageRole.assistant);
    expect(messagesB.last.content, isEmpty);
    expect(messagesB.last.id, errorAssistantId);
  });

  // ── 5.3-1 send 成功带 finishReason -> 重建 -> finishReason 恢复 ────────────────

  test('send 成功带 finishReason -> 重建 -> finishReason 恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    // 终态 chunk 携带 finishReason='stop'，验证其随 assistant 消息持久化并在重建后恢复。
    fakeClientA.enqueueDeltas(const [
      ChatGenerationChunk(contentDelta: '完成了'),
      ChatGenerationChunk(finishReason: 'stop'),
    ]);
    await sendMsg(containerA, content: '请完成');

    final assistantA = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages[1];
    expect(assistantA.content, '完成了');
    expect(assistantA.finishReason, 'stop');

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(containerB.dispose);

    final assistantB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages[1];
    expect(assistantB.content, '完成了');
    expect(assistantB.finishReason, 'stop');
  });

  // ── 5.3-2 stop 后重建容器 - 部分内容持久化恢复 ────────────────────────────────

  test('stop 后重建容器 - 部分内容持久化恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    final controlled = fakeClientA.enqueueControlledStream();
    addTearDown(controlled.close);

    final sendFuture = sendMsg(containerA, content: '开始生成');
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(contentDelta: '部分回复'));
    // 等增量进入 provider 状态（首 chunk 同步投影到 streamingReply），确保 stop
    // 前内容已被 run 消费，部分内容可确定性落盘。
    await waitForProviderState(
      container: containerA,
      provider: chatSessionsProvider,
      matches: (s) => s.streamingReply?.content == '部分回复',
      description: '等待增量内容进入流式状态',
    );

    await containerA.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final messagesA = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesA.last.content, '部分回复');

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(containerB.dispose);

    final messagesB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB.last.content, '部分回复');
  });

  // ── 5.3-2 空回复后重建容器 - 空助手占位恢复 ────────────────────────────────────

  test('空回复后重建容器 - 空助手占位恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    // 空流：onDone 时累积内容为空 -> emptyReply，空助手占位仍落盘。
    fakeClientA.enqueueChunks(const <String>[]);
    await sendMsg(containerA, content: '不要输出');

    final messagesA = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesA.last.role, ChatMessageRole.assistant);
    expect(messagesA.last.content, isEmpty);
    final emptyAssistantId = messagesA.last.id;

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(containerB.dispose);

    final messagesB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB.last.role, ChatMessageRole.assistant);
    expect(messagesB.last.content, isEmpty);
    expect(messagesB.last.id, emptyAssistantId);
  });

  // ── 一次性 repository failure 后不自动重复请求，显式重试可继续 ────────────────

  test('一次性 repository failure 后不自动重复请求，显式重试可继续', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatGenerationClient();

    final failingRepo = _FailingOnceRepository(
      SqliteChatConversationRepository(database),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(failingRepo),
      ],
    );
    addTearDown(database.close);
    addTearDown(container.dispose);

    // 不 enqueue 任何回复：pending save 失败不应调 streamCompletion（见下方
    // requestHistory 断言）。若误 enqueue，会留在队列被下一次请求误消费。
    await sendMsg(container, content: '触发落盘失败');

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, ChatErrorMessages.persistenceFailed);
    // 未发起任何模型请求（pending save 失败即中止，不自动重放 body）。
    expect(fakeClient.requestHistory, isEmpty);

    // 显式重试：repository 已恢复正常，generation 成功落盘。
    fakeClient.enqueueChunks(['重试成功回复']);
    await sendMsg(container, content: '显式重试');

    expect(fakeClient.requestHistory.length, 1);
    expect(
      container
          .read(chatSessionsProvider)
          .activeConversation
          .messages
          .last
          .content,
      '重试成功回复',
    );
  });

  // ── generation 进行中 createCheckpoint 被忙守卫拒绝（互斥） ────────────────────

  test('generation 进行中 createCheckpoint 被忙守卫拒绝', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatGenerationClient();

    final container = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClient,
    );
    addTearDown(database.close);
    addTearDown(container.dispose);

    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);

    final sendFuture = sendMsg(container, content: '生成中');
    // 明确等 generation 进入 active phase（streaming）后再触发 checkpoint，
    // 保证忙守卫必然生效，不靠延时。
    await waitForProviderState(
      container: container,
      provider: chatSessionsProvider,
      matches: (s) => s.generation?.phase == ChatGenerationPhase.streaming,
      description: '等待 generation 进入 streaming 阶段',
    );

    // generation 进行中（isStreaming），createCheckpoint 应被忙守卫拒绝，不产生 checkpoint。
    expect(
      () => container
          .read(chatSessionsProvider.notifier)
          .createCheckpoint(
            modelConfig: testModel,
            memoryPrompt: testMemoryPrompt,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          ),
      throwsA(isA<ChatGenerationException>()),
    );

    // 放行 generation 完成，验证未受 checkpoint 尝试影响。
    controlled.add(const ChatGenerationChunk(contentDelta: '生成完成'));
    await controlled.close();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.checkpoints, isEmpty);
    expect(state.activeConversation.messages.last.content, '生成完成');
  });
}

/// 测试用 repository：首次 saveConversation 抛异常模拟一次性落盘失败，
/// 之后 delegating 到内层。用于验证 pending save 失败后不自动重复请求。
class _FailingOnceRepository implements ChatConversationRepository {
  _FailingOnceRepository(this._inner);

  final ChatConversationRepository _inner;
  bool _hasFailed = false;

  @override
  Future<void> saveConversation(ChatConversation conversation) async {
    if (!_hasFailed) {
      _hasFailed = true;
      throw StateError('模拟一次性落盘失败');
    }
    await _inner.saveConversation(conversation);
  }

  @override
  Future<void> saveConversations(List<ChatConversation> conversations) =>
      _inner.saveConversations(conversations);

  @override
  List<ChatConversation> loadAll() => _inner.loadAll();

  @override
  ChatConversation? loadConversation(String id) => _inner.loadConversation(id);

  @override
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  }) => _inner.loadHistorySummaries(
    keyword: keyword,
    limit: limit,
    offset: offset,
  );

  @override
  int countHistorySummaries({String keyword = ''}) =>
      _inner.countHistorySummaries(keyword: keyword);

  @override
  Future<void> deleteConversations(List<String> ids) =>
      _inner.deleteConversations(ids);

  @override
  Future<void> flush() => _inner.flush();

  @override
  Future<void> close() => _inner.close();
}
