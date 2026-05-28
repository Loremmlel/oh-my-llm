/// 对话生命周期集成测试。
///
/// 验证对话数据的完整持久化链路：创建 → 写入 SQLite → 容器重建（模拟重启）→ 数据完整恢复。
/// 覆盖消息持久化、分支编辑保留、检查点保留和流异常后的错误保留。
/// 所有测试在 ProviderContainer 级别运行，不涉及 UI。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 对话持久化→容器重建→数据完整恢复 ──────────────────────────────────────────

  test('对话持久化→容器重建→数据完整恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatCompletionClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClientA),
      ],
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

    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
    );
    addTearDown(() {
      containerB.dispose();
    });

    final stateB = containerB.read(chatSessionsProvider);
    expect(stateB.conversations.length, 1);
    expect(stateB.activeConversation.messages.length, messageCountA);
    expect(stateB.activeConversation.messages[0].content, '你好');
    expect(stateB.activeConversation.messages[1].content, firstAssistantContent);
  });

  // ── 分支编辑后重建容器 — 分支选择保留 ────────────────────────────────────────

  test('分支编辑后重建容器 — 分支选择保留', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatCompletionClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClientA),
      ],
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

    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
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

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClientA),
      ],
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

    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
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

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClientA),
      ],
    );
    addTearDown(database.close);

    fakeClientA.enqueueError(ChatCompletionException('模拟的网络错误'));
    await containerA.read(chatSessionsProvider.notifier).sendMessage(
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

    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
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
}
