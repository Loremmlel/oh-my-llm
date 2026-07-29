/// 对话生命周期集成测试。
///
/// 验证对话数据的完整持久化链路：创建 → 写入 SQLite → 容器重建（模拟重启）→ 数据完整恢复。
/// 覆盖消息持久化、分支编辑保留、检查点保留和流异常后的错误保留。
/// 所有测试在 ProviderContainer 级别运行，不涉及 UI。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 对话持久化→容器重建→数据完整恢复 ──────────────────────────────────────────

  test('对话持久化→容器重建→数据完整恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatCompletionClient();

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
      fakeClient: FakeChatCompletionClient(),
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

  // ── 分支编辑后重建容器 — 分支选择保留 ────────────────────────────────────────

  test('分支编辑后重建容器 — 分支选择保留', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatCompletionClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    fakeClientA.enqueueChunks(['第一次回复']);
    fakeClientA.enqueueChunks(['重新生成的回复']);
    await sendMsg(containerA, content: '原始问题');

    final userMessageId = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .first
        .id;

    await containerA
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: userMessageId, nextContent: '修改后的问题');

    final messagesA = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesA.length, 2);
    expect(messagesA[0].content, '修改后的问题');
    final branchAssistantContent = messagesA[1].content;
    expect(branchAssistantContent, '重新生成的回复');

    final messageCountA = messagesA.length;

    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatCompletionClient(),
    );
    addTearDown(() {
      containerB.dispose();
    });

    final messagesB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB.length, messageCountA);
    expect(messagesB[0].content, '修改后的问题');
    expect(messagesB[1].content, branchAssistantContent);
  });

  // ── 检查点创建后重建容器 — 检查点保留 ────────────────────────────────────────

  test('检查点创建后重建容器 — 检查点保留', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatCompletionClient();

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
      fakeClient: FakeChatCompletionClient(),
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
    final fakeClientA = FakeChatCompletionClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    fakeClientA.enqueueError(ChatCompletionException('模拟的网络错误'));
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
      fakeClient: FakeChatCompletionClient(),
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
    final fakeClientA = FakeChatCompletionClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    // 终态 chunk 携带 finishReason='stop'，验证其随 assistant 消息持久化并在重建后恢复。
    fakeClientA.enqueueDeltas(const [
      ChatCompletionChunk(contentDelta: '完成了'),
      ChatCompletionChunk(finishReason: 'stop'),
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
      fakeClient: FakeChatCompletionClient(),
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
    final fakeClientA = FakeChatCompletionClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClientA,
    );
    addTearDown(database.close);

    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(() {
      streamController.close();
    });
    fakeClientA.enqueueStream(streamController.stream);

    final sendFuture = sendMsg(containerA, content: '开始生成');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分回复'));
    await Future<void>.delayed(const Duration(milliseconds: 5));

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
      fakeClient: FakeChatCompletionClient(),
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
    final fakeClientA = FakeChatCompletionClient();

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
      fakeClient: FakeChatCompletionClient(),
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

  // ── 5.3-3 generation 期间 stop 后新 generation 不被旧回调覆盖 ──────────────────

  test('generation 期间 stop 后新 generation 不被旧回调覆盖', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final container = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClient,
    );
    addTearDown(database.close);
    addTearDown(container.dispose);

    // A：streaming 中 stop，保留部分内容。
    final streamA = StreamController<ChatCompletionChunk>();
    addTearDown(() {
      streamA.close();
    });
    fakeClient.enqueueStream(streamA.stream);
    final sendA = sendMsg(container, content: '生成 A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    streamA.add(const ChatCompletionChunk(contentDelta: 'A 部分'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendA;

    // B：新 generation 完整回复，验证旧 A 的回调不覆盖 B。
    fakeClient.enqueueChunks(['B 完整回复']);
    await sendMsg(container, content: '生成 B');

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    // [user A, assistant A(部分), user B, assistant B(完整)]
    expect(messages.length, 4);
    expect(messages[1].content, 'A 部分');
    expect(messages[3].content, 'B 完整回复');
    // 仅 A、B 各一次模型请求，无重复持久化触发的重复请求。
    expect(fakeClient.requestHistory.length, 2);
  });

  // ── 5.3-4 一次性 repository failure 后不自动重复请求，显式重试可继续 ────────────

  test('一次性 repository failure 后不自动重复请求，显式重试可继续', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final failingRepo = _FailingOnceRepository(
      SqliteChatConversationRepository(database),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
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

  // ── 5.3-5 generation 进行中 createCheckpoint 被忙守卫拒绝（互斥） ────────────────

  test('generation 进行中 createCheckpoint 被忙守卫拒绝', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final container = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClient,
    );
    addTearDown(database.close);
    addTearDown(container.dispose);

    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(() {
      streamController.close();
    });
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg(container, content: '生成中');
    await Future<void>.delayed(const Duration(milliseconds: 5));

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
      throwsA(isA<ChatCompletionException>()),
    );

    // 放行 generation 完成，验证未受 checkpoint 尝试影响。
    streamController.add(const ChatCompletionChunk(contentDelta: '生成完成'));
    await streamController.close();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.checkpoints, isEmpty);
    expect(state.activeConversation.messages.last.content, '生成完成');
  });
}

/// 测试用 repository：首次 saveConversation 抛异常模拟一次性落盘失败，
/// 之后 delegating 到内层。用于验证 pending save 失败后不自动重复请求（5.3-4）。
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
