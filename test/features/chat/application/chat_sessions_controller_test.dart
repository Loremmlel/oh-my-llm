import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';

import '../chat_screen/chat_screen_test_helpers.dart';

/// 测试用模型配置，和 SharedPreferences 中的 id 一致，确保 _resolveModelConfig 能找到它。
final _testModel = LlmModelConfig(
  id: 'model-1',
  displayName: 'Test Model',
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test',
  modelName: 'test-model',
  supportsReasoning: false,
);

final _memoryPrompt = MemoryPrompt(
  id: 'memory-1',
  name: '研发总结',
  content: '请总结当前对话中的关键事实、约束与待办。',
  updatedAt: DateTime(2026, 5, 1),
);

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
        items: const [
          LlmProviderConfig(
            id: 'provider-1',
            name: 'Test Provider',
            apiUrl: 'https://api.example.com/v1/chat/completions',
            apiKey: 'sk-test',
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'Test Model',
                modelName: 'test-model',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        toJson: (provider) => provider.toJson(),
      ),
    });
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    // 通过 Repository API 将预设提示词写入 SQLite
    await presetPromptRepository.saveAll(database, [
      PresetPrompt(
        id: 'prompt-1',
        name: '模板一',
        messages: const [
          PromptMessage(
            id: 'prompt-1-message-1',
            role: PromptMessageRole.user,
            content: '模板一前置',
            placement: PromptMessagePlacement.before,
          ),
        ],
        updatedAt: DateTime(2026, 4, 30),
      ),
      PresetPrompt(
        id: 'prompt-2',
        name: '模板二',
        messages: const [
          PromptMessage(
            id: 'prompt-2-message-1',
            role: PromptMessageRole.user,
            content: '模板二前置',
            placement: PromptMessagePlacement.before,
          ),
        ],
        updatedAt: DateTime(2026, 4, 30, 0, 1),
      ),
    ]);
    fakeClient = FakeChatCompletionClient();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(() {
      container.dispose();
      database.close();
    });
  });

  /// 向活动会话发送一条消息并等待流式回复完成。
  Future<void> sendMsg(
    String content, {
    Duration? retryDelay,
  }) =>
      container.read(chatSessionsProvider.notifier).sendMessage(
            content: content,
            modelConfig: _testModel,
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
            retryDelay: retryDelay,
          );

  // ── 初始化 ─────────────────────────────────────────────────────────────────

  test('空数据库启动时自动创建一个空白会话', () {
    final state = container.read(chatSessionsProvider);
    expect(state.conversations.length, 1);
    expect(state.activeConversation.hasMessages, isFalse);
    expect(state.historyRevision, 0);
  });

  test('重新创建 container 时从数据库恢复已有会话', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('你好');

    // 模拟应用重启：复用同一数据库，新建 ProviderContainer
    final container2 = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(
          FakeChatCompletionClient(),
        ),
      ],
    );
    addTearDown(container2.dispose);

    final state2 = container2.read(chatSessionsProvider);
    expect(state2.conversations.length, 1);
    expect(state2.activeConversation.hasMessages, isTrue);
  });

  // ── createConversation ─────────────────────────────────────────────────────

  test('当前会话为空时 createConversation 为空操作', () async {
    await container.read(chatSessionsProvider.notifier).createConversation();
    expect(container.read(chatSessionsProvider).conversations.length, 1);
  });

  test('当前会话有消息时 createConversation 新建并切换', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('第一条消息');

    final revisionBefore = container.read(chatSessionsProvider).historyRevision;
    await container.read(chatSessionsProvider.notifier).createConversation();

    final state = container.read(chatSessionsProvider);
    expect(state.conversations.length, 2);
    expect(state.activeConversation.hasMessages, isFalse);
    expect(state.historyRevision, greaterThan(revisionBefore));
  });

  // ── selectConversation ─────────────────────────────────────────────────────

  test('selectConversation 切换到指定会话', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('消息');
    final firstId = container.read(chatSessionsProvider).activeConversationId;

    await container.read(chatSessionsProvider.notifier).createConversation();
    expect(
      container.read(chatSessionsProvider).activeConversationId,
      isNot(firstId),
    );

    container.read(chatSessionsProvider.notifier).selectConversation(firstId);
    expect(container.read(chatSessionsProvider).activeConversationId, firstId);
  });

  test('selectConversation 对不存在的 id 为空操作', () {
    final initialId = container.read(chatSessionsProvider).activeConversationId;
    container
        .read(chatSessionsProvider.notifier)
        .selectConversation('non-existent');
    expect(
      container.read(chatSessionsProvider).activeConversationId,
      initialId,
    );
  });

  // ── renameActiveConversation ───────────────────────────────────────────────

  test('renameActiveConversation 更新标题', () async {
    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('新标题');
    expect(
      container.read(chatSessionsProvider).activeConversation.title,
      '新标题',
    );
  });

  test('renameActiveConversation 忽略纯空白名称', () async {
    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('原标题');
    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('   ');
    expect(
      container.read(chatSessionsProvider).activeConversation.title,
      '原标题',
    );
  });

  // ── renameConversation ─────────────────────────────────────────────────────

  test('renameConversation 按 id 重命名指定会话', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('消息');
    final id = container.read(chatSessionsProvider).activeConversationId;

    await container
        .read(chatSessionsProvider.notifier)
        .renameConversation(conversationId: id, title: '重命名后');

    final renamed = container
        .read(chatSessionsProvider)
        .conversations
        .firstWhere((c) => c.id == id);
    expect(renamed.title, '重命名后');
  });

  test('renameActiveConversation 后继续发送消息不会重置自定义标题', () async {
    fakeClient.enqueueChunks(['第一次回复']);
    await sendMsg('第一条消息');

    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('手动标题');

    fakeClient.enqueueChunks(['第二次回复']);
    await sendMsg('第二条消息');

    final activeConversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    expect(activeConversation.title, '手动标题');
    expect(activeConversation.resolvedTitle, '手动标题');
  });

  test('空白会话先自定义标题后首次发送消息不会重置标题', () async {
    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('空白草稿标题');

    fakeClient.enqueueChunks(['首次回复']);
    await sendMsg('首条消息');

    final activeConversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    expect(activeConversation.title, '空白草稿标题');
    expect(activeConversation.resolvedTitle, '空白草稿标题');
  });

  // ── deleteConversations ────────────────────────────────────────────────────

  test('deleteConversations 删除指定会话', () async {
    fakeClient.enqueueChunks(['回复1']);
    fakeClient.enqueueChunks(['回复2']);
    await sendMsg('消息1');

    await container.read(chatSessionsProvider.notifier).createConversation();
    await sendMsg('消息2');

    final state = container.read(chatSessionsProvider);
    expect(state.conversations.length, 2);

    final toDelete = state.conversations.last.id;
    await container.read(chatSessionsProvider.notifier).deleteConversations({
      toDelete,
    });

    final after = container.read(chatSessionsProvider);
    expect(after.conversations.length, 1);
    expect(after.conversations.any((c) => c.id == toDelete), isFalse);
  });

  test('deleteConversations 全部删除时创建空白回退会话', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('消息');

    final id = container.read(chatSessionsProvider).activeConversationId;
    await container.read(chatSessionsProvider.notifier).deleteConversations({
      id,
    });

    final state = container.read(chatSessionsProvider);
    expect(state.conversations.length, 1);
    expect(state.activeConversation.hasMessages, isFalse);
  });

  // ── sendMessage ────────────────────────────────────────────────────────────

  test('sendMessage 添加用户消息和助手回复', () async {
    fakeClient.enqueueChunks(['你好！']);
    await sendMsg('你好');

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.length, 2);
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[0].content, '你好');
    expect(messages[1].role, ChatMessageRole.assistant);
    expect(messages[1].content, '你好！');
    expect(container.read(chatSessionsProvider).isStreaming, isFalse);
  });

  test('sendMessage 会裁剪有效输入并忽略纯空白内容', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('  你好  ');

    final notifier = container.read(chatSessionsProvider.notifier);
    await notifier.sendMessage(
      content: '   ',
      modelConfig: _testModel,
      presetPrompt: null,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
    );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages, hasLength(2));
    expect(messages[0].content, '你好');
    expect(messages[1].content, '回复');
  });

  test('setMessagesExcluded 会把排除状态保存到当前会话', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('第一轮问题');

    final assistantMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantMessageId], excluded: true);

    final conversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    expect(conversation.excludedMessageIds, [assistantMessageId]);
  });

  test('sendMessage 会跳过已排除的历史消息', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('第一轮问题');

    final assistantMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantMessageId], excluded: true);

    fakeClient.enqueueChunks(['第二轮回复']);
    await sendMsg('第二轮问题');

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '第二轮问题'],
    );
  });

  test('sendMessage 错误时设置 errorMessage 并清除 isStreaming', () async {
    fakeClient.enqueueError(ChatCompletionException('API 请求失败'));
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessage 错误且无部分内容时保留空白占位节点', () async {
    fakeClient.enqueueError(ChatCompletionException('请求失败'));
    await sendMsg('触发错误');

    // 空流失败后空白 assistant 节点保留在树中，用户消息 + 占位节点共 2 条
    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages.length, 2);
    expect(messages.first.role, ChatMessageRole.user);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessageAssistantId, isNotNull);
  });

  test('sendMessage 仅收到 reasoning 后失败时保留占位 assistant 节点', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('先思考再失败');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(reasoningDelta: '思考中'));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.addError(const ChatCompletionException('请求失败'));
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, '请求失败');
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.last.role, ChatMessageRole.assistant);
    expect(state.activeConversation.messages.last.reasoningContent, '思考中');
    expect(state.errorMessageAssistantId, state.activeConversation.messages.last.id);
  });

  test('sendMessage 空回复时保留助手占位节点并设置内联错误', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.role, ChatMessageRole.assistant);
    expect(state.activeConversation.messages.last.content, isEmpty);
    expect(state.emptyReplyAssistantId, state.activeConversation.messages.last.id);
    expect(state.errorMessage, contains('空回复'));
    expect(state.errorMessageAssistantId, state.activeConversation.messages.last.id);
    expect(state.isStreaming, isFalse);
  });

  test('createCheckpoint 保存检查点并记录来源提示词名称', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('先产生一些上下文');

    fakeClient.enqueueChunks(['这是总结后的检查点内容']);

    final checkpoint = await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: _testModel,
          memoryPrompt: _memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final conversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    expect(conversation.checkpoints, hasLength(1));
    expect(conversation.checkpoints.single.id, checkpoint.id);
    expect(conversation.checkpoints.single.content, '这是总结后的检查点内容');
    expect(conversation.checkpoints.single.sourceMemoryPromptName, '研发总结');
    expect(container.read(chatSessionsProvider).isCheckpointing, isFalse);
    expect(
      fakeClient.lastRequestMessages.map((item) => item.content).join('\n'),
      contains('请总结当前对话中的关键事实、约束与待办。'),
    );
  });

  test('createCheckpoint 会附带当前选中的前置提示词', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('需要带前置提示词的上下文');
    await container
        .read(presetPromptsProvider.notifier)
        .upsert(
          PresetPrompt(
            id: 'prompt-1',
            name: '模板一',
            messages: const [
              PromptMessage(
                id: 'prompt-1-message-1',
                role: PromptMessageRole.user,
                content: '模板一前置',
                placement: PromptMessagePlacement.before,
              ),
            ],
            updatedAt: DateTime(2026, 4, 30),
          ),
        );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: 'prompt-1',
        );

    fakeClient.enqueueChunks(['检查点总结']);
    await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: _testModel,
          memoryPrompt: _memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final requestContents = fakeClient.lastRequestMessages
        .map((message) => message.content)
        .toList(growable: false);
    expect(requestContents, contains('模板一前置'));
    expect(requestContents.last, contains('请按照以下记忆总结提示词生成新的检查点'));
  });

  test('createCheckpoint 会跳过已排除的对话消息', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('需要被排除的上下文');

    final assistantMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantMessageId], excluded: true);

    fakeClient.enqueueChunks(['检查点总结']);
    await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: _testModel,
          memoryPrompt: _memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    final requestContents = fakeClient.lastRequestMessages
        .map((message) => message.content)
        .toList(growable: false);
    expect(requestContents, contains('需要被排除的上下文'));
    expect(requestContents, isNot(contains('首轮回复')));
  });

  test('选中检查点后发送消息只携带检查点 system 消息与增量消息', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('第一轮问题');

    fakeClient.enqueueChunks(['检查点总结']);
    final checkpoint = await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: _testModel,
          memoryPrompt: _memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );

    container
        .read(chatSessionsProvider.notifier)
        .selectActiveCheckpoint(checkpoint.id);

    fakeClient.enqueueChunks(['第二轮回复']);
    await sendMsg('第二轮问题');

    final lastRequest = fakeClient.requestHistory.last;
    expect(lastRequest, hasLength(2));
    expect(lastRequest.first.role, ChatMessageRole.system);
    expect(lastRequest.first.content, contains('检查点 1'));
    expect(lastRequest.first.content, contains('检查点总结'));
    expect(lastRequest.last.role, ChatMessageRole.user);
    expect(lastRequest.last.content, '第二轮问题');
  });

  test('选中检查点后助手回复会写入 appliedCheckpointTitle', () async {
    fakeClient.enqueueChunks(['原始回复']);
    await sendMsg('原始问题');

    fakeClient.enqueueChunks(['新的检查点']);
    final checkpoint = await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: _testModel,
          memoryPrompt: _memoryPrompt,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    container
        .read(chatSessionsProvider.notifier)
        .selectActiveCheckpoint(checkpoint.id);

    fakeClient.enqueueChunks(['使用检查点后的回复']);
    await sendMsg('下一条问题');

    final assistant = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last;
    expect(assistant.role, ChatMessageRole.assistant);
    expect(assistant.content, '使用检查点后的回复');
    expect(assistant.appliedCheckpointTitle, '检查点 1');
  });

  // ── editMessage ────────────────────────────────────────────────────────────

  test('editMessage 创建新分支并重新生成回复', () async {
    fakeClient.enqueueChunks(['第一次回复']);
    fakeClient.enqueueChunks(['重新生成的回复']);
    await sendMsg('原始问题');

    final userMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .first
        .id;

    await container
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: userMessageId, nextContent: '修改后的问题');

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.length, 2);
    expect(messages[0].content, '修改后的问题');
    expect(messages[1].content, '重新生成的回复');
  });

  test('editMessage 忽略纯空白内容', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('原始问题');

    final userMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .first
        .id;

    await container
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: userMessageId, nextContent: '   ');

    // 消息树不应改变
    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages[0].content, '原始问题');
  });

  // ── retryLatestAssistant ───────────────────────────────────────────────────

  test('retryLatestAssistant 无助手消息时设置 errorMessage', () async {
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();
    expect(container.read(chatSessionsProvider).errorMessage, isNotNull);
  });

  test('retryLatestAssistant 可重试失败后的最新助手消息', () async {
    fakeClient.enqueueError(ChatCompletionException('503 unavailable'));
    await sendMsg('先失败后重试');
    final failureState = container.read(chatSessionsProvider);
    // 空内容失败后空白节点保留在树中，用户消息 + 占位节点共 2 条
    expect(failureState.activeConversation.messages, hasLength(2));
    expect(failureState.errorMessage, isNotNull);
    expect(failureState.errorMessageAssistantId, isNotNull);

    fakeClient.enqueueChunks(['重试成功回复']);
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages, hasLength(2));
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[1].role, ChatMessageRole.assistant);
    expect(messages[1].content, '重试成功回复');
    expect(state.errorMessage, isNull);
    expect(state.errorMessageAssistantId, isNull);

    final userMessage = messages.first;
    final assistantChildren = state.activeConversation.messageNodes
        .where((node) {
          return node.role == ChatMessageRole.assistant &&
              node.parentId == userMessage.id;
        })
        .toList(growable: false);
    expect(assistantChildren, hasLength(1));
  });

  test('sendMessage 未知异常时在错误信息中包含堆栈', () async {
    fakeClient.enqueueError(StateError('boom'));
    await sendMsg('触发未知异常');

    final errorMessage = container.read(chatSessionsProvider).errorMessage;
    expect(errorMessage, isNotNull);
    expect(errorMessage, contains('Bad state: boom'));
    expect(errorMessage, contains('```text'));
  });

  test('stopStreaming 保留已收到的部分回复', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('请开始生成');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分回复'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.activeConversation.messages.last.content, '部分回复');
    expect(state.activeConversation.messages.last.isStreaming, isFalse);
  });

  test('stopStreaming 在无内容时保留空助手占位以便重试', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('不要输出任何内容');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    // 终止后保留空助手占位节点，便于用户重试。
    expect(messages, hasLength(2));
    expect(messages.first.role, ChatMessageRole.user);
    expect(messages.last.role, ChatMessageRole.assistant);
    expect(messages.last.content, isEmpty);
    expect(messages.last.isStreaming, isFalse);
    // 空回复标记指向该助手节点，UI 可显示终止提示卡片。
    expect(state.emptyReplyAssistantId, messages.last.id);
    expect(state.errorMessageAssistantId, messages.last.id);
  });

  test('deleteMessage 删除当前助手分支后回退到剩余版本', () async {
    fakeClient
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['重试回复']);
    await sendMsg('测试删除分支');
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final stateBeforeDelete = container.read(chatSessionsProvider);
    final latestAssistant = stateBeforeDelete.activeConversation.messages.last;
    await container
        .read(chatSessionsProvider.notifier)
        .deleteMessage(
          messageId: latestAssistant.id,
          scope: ChatMessageDeletionScope.currentBranch,
        );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.last.content, '首次回复');
    final assistantChildren = container
        .read(chatSessionsProvider)
        .activeConversation
        .messageNodes
        .where((node) {
          return node.role == ChatMessageRole.assistant &&
              node.parentId == messages.first.id;
        })
        .toList(growable: false);
    expect(assistantChildren, hasLength(1));
  });

  test('deleteMessage 删除全部助手版本后保留父用户消息', () async {
    fakeClient
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['重试回复']);
    await sendMsg('测试全部删除');
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final latestAssistant = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last;
    await container
        .read(chatSessionsProvider.notifier)
        .deleteMessage(
          messageId: latestAssistant.id,
          scope: ChatMessageDeletionScope.allBranches,
        );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);
  });

  test('deleteMessage 会同步清理已排除消息 id', () async {
    fakeClient.enqueueChunks(['首轮回复']);
    await sendMsg('测试删除排除状态');

    final assistantMessageId = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .last
        .id;
    await container
        .read(chatSessionsProvider.notifier)
        .setMessagesExcluded(messageIds: [assistantMessageId], excluded: true);

    await container
        .read(chatSessionsProvider.notifier)
        .deleteMessage(
          messageId: assistantMessageId,
          scope: ChatMessageDeletionScope.currentBranch,
        );

    expect(
      container
          .read(chatSessionsProvider)
          .activeConversation
          .excludedMessageIds,
      isEmpty,
    );
  });

  test('deleteMessage 删除当前用户分支后切回剩余根分支', () async {
    fakeClient
      ..enqueueChunks(['原始回复一'])
      ..enqueueChunks(['原始回复二'])
      ..enqueueChunks(['编辑后回复一']);
    await sendMsg('原始用户1');
    await sendMsg('原始用户2');

    final beforeEdit = container.read(chatSessionsProvider).activeConversation;
    final originalRootUser = beforeEdit.messageNodes.firstWhere((message) {
      return message.role == ChatMessageRole.user &&
          (message.parentId ?? rootConversationParentId) ==
              rootConversationParentId;
    });
    await container
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: originalRootUser.id, nextContent: '编辑后的用户1');

    final currentRootUser = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages
        .first;
    await container
        .read(chatSessionsProvider.notifier)
        .deleteMessage(
          messageId: currentRootUser.id,
          scope: ChatMessageDeletionScope.currentBranch,
        );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.first.content, '原始用户1');
    expect(messages.last.content, '原始回复二');
  });

  // ── historyRevision ────────────────────────────────────────────────────────

  test('historyRevision 在每次写操作后递增', () async {
    int revision() => container.read(chatSessionsProvider).historyRevision;
    final r0 = revision();

    fakeClient.enqueueChunks(['回复']);
    await sendMsg('消息');
    final r1 = revision();
    expect(r1, greaterThan(r0));

    await container
        .read(chatSessionsProvider.notifier)
        .renameActiveConversation('新名字');
    expect(revision(), greaterThan(r1));
  });

  // ── 自动重试 ─────────────────────────────────────────────────────────────────

  test('autoRetryEnabled=true 时正常发送并收到回复', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueChunks(['自动重试回复']);

    await sendMsg('你好', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages.length, 2);
    expect(messages.last.content, '自动重试回复');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessageWithAutoRetry 首次失败后重试成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatCompletionException('连接超时'));
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '重试成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessageWithAutoRetry 连续两次失败后第三次成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatCompletionException('第一次失败'));
    fakeClient.enqueueError(ChatCompletionException('第二次失败'));
    fakeClient.enqueueChunks(['第三次成功']);

    await sendMsg('测试多次重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '第三次成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(fakeClient.requestHistory.length, 3);
  });

  test('stopStreaming 在 auto-retry 等待期间取消重试', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 手动设置 isAutoRetryWaiting 状态
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = container.read(chatSessionsProvider).copyWith(
      isAutoRetryWaiting: true,
      autoRetryCount: 3,
      errorMessage: '之前的错误',
    );

    await notifier.stopStreaming();

    final state = container.read(chatSessionsProvider);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(state.autoRetryCount, 0);
    expect(state.errorMessage, isNull);
  });

  test('sendMessageWithAutoRetry 成功后清除之前的错误信息', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatCompletionException('请求失败'));
    fakeClient.enqueueChunks(['重试成功']);

    await sendMsg('测试清除错误', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNull);
    expect(state.errorMessageAssistantId, isNull);
  });

  test('autoRetryWaiting 期间 sendMessage 被 _isBusy 阻止', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 手动设置 isAutoRetryWaiting=true
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = container.read(chatSessionsProvider).copyWith(
      isAutoRetryWaiting: true,
    );

    fakeClient.enqueueChunks(['should not be sent']);
    await sendMsg('不会被发送的消息');

    // _isBusy 应阻止发送，没有请求被发出
    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.hasMessages, isFalse);
    expect(fakeClient.requestHistory, isEmpty);
  });

  test('autoRetryEnabled 默认值在 sendMessage 时不触发自动重试', () async {
    // 不设置 autoRetryEnabled（默认 false）
    fakeClient.enqueueError(ChatCompletionException('错误'));

    await sendMsg('普通发送');

    // 一次请求就失败了，没有重试
    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.autoRetryCount, 0);
    expect(state.isAutoRetryWaiting, isFalse);
    expect(fakeClient.requestHistory.length, 1);
  });

  test('stopStreaming 在过渡窗口期间被调用后旧重试不继续', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 第一次请求会失败，重试会有一个可控的等待窗口
    fakeClient.enqueueError(ChatCompletionException('首次失败'));

    // 用较大的 retryDelay 创造宽余的重试窗口，避免 CI timing 脆弱
    final sendFuture = sendMsg('test A', retryDelay: const Duration(seconds: 1));

    // 等第一个请求发出并失败，重试循环进入等待窗口
    // 轮询等待 isAutoRetryWaiting 变为 true，最多等 5 秒
    bool waiting = false;
    for (int i = 0; i < 50; i++) {
      waiting = container.read(chatSessionsProvider).isAutoRetryWaiting;
      if (waiting) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(waiting, isTrue);

    // 此时旧重试在等待窗口中，调用 stopStreaming 取消
    await container.read(chatSessionsProvider.notifier).stopStreaming();

    // _isBusy 已为 false（isAutoRetryWaiting 被清除），发送新消息
    fakeClient.enqueueChunks(['回复 B']);
    await sendMsg('test B');

    // 等待旧重试循环退出
    await sendFuture;

    // 只有 2 次请求：test A 的首次失败 + test B 的成功
    // 旧重试循环在恢复后通过 autoRetryCancelled / requestGeneration 检查退出，未发出额外请求
    expect(fakeClient.requestHistory.length, 2);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '回复 B');
    expect(state.errorMessage, isNull);
    expect(state.isStreaming, isFalse);
  });

  // ── 空回复 ──────────────────────────────────────────────────────────────────

  test('autoRetry 遇到空回复继续重试直到成功', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueChunks(['']);        // 首次：空回复
    fakeClient.enqueueChunks(['终于成功']); // 重试：正常回复

    await sendMsg('测试空回复重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '终于成功');
    expect(fakeClient.requestHistory.length, 2);
    expect(state.errorMessage, isNull);
    expect(state.emptyReplyAssistantId, isNull);
  });

  test('autoRetry 连续空回复达到上限退出', () async {
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);

    // 设置 maxRetryCount=2，3 次空回复后触发上限
    final prefs = container.read(sharedPreferencesProvider);
    await prefs.setString(
      'settings.auto_retry',
      '{"maxJitterSeconds":0,"maxRetryCount":2}',
    );
    fakeClient.enqueueChunks(['']); // 第 1 次空
    fakeClient.enqueueChunks(['']); // 第 2 次空
    fakeClient.enqueueChunks(['']); // 第 3 次空（超出上限）

    await sendMsg('测试上限', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('重试已达上限'));
  });

  test('手动重试空回复时删除空节点并重试', () async {
    fakeClient.enqueueChunks(['']);        // 空回复
    fakeClient.enqueueChunks(['重试回复']);

    await sendMsg('测试空回复');

    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.length, 2); // user + new assistant
    expect(state.activeConversation.messages.last.content, '重试回复');
    expect(state.errorMessage, isNull);
  });

  test('流式错误且空内容时保留空占位节点并设置内联错误', () async {
    fakeClient.enqueueError(ChatCompletionException('模拟流式错误'));

    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
    // 空白 assistant 节点保留在树中，errorMessageAssistantId 指向它
    expect(state.activeConversation.messages, hasLength(2));
    expect(state.errorMessageAssistantId, state.activeConversation.messages.last.id);
    expect(state.activeConversation.messages.last.role, ChatMessageRole.assistant);
    expect(state.activeConversation.messages.last.content, isEmpty);
  });

  test('空回复且无自动重试时不自动重试', () async {
    // autoRetryEnabled 默认 false
    fakeClient.enqueueChunks(['']);

    await sendMsg('测试');

    final state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, isNotNull);
    expect(fakeClient.requestHistory.length, 1); // 仅一次，不重试
  });

  // ── emptyReplyAssistantId 边界 ──────────────────────────────────────────

  test('切换会话清除 emptyReplyAssistantId', () async {
    // 准备两个会话
    fakeClient.enqueueChunks(['回复1']);
    await sendMsg('第一条消息');
    final firstId = container.read(chatSessionsProvider).activeConversationId;

    fakeClient.enqueueChunks(['回复2']);
    await container.read(chatSessionsProvider.notifier).createConversation();
    await sendMsg('第二条消息');
    final secondId = container.read(chatSessionsProvider).activeConversationId;
    expect(firstId, isNot(secondId));

    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');
    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, 'test-id');

    // 切换到第一个会话应清除 emptyReplyAssistantId
    notifier.selectConversation(firstId);
    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, isNull);
  });

  test('空回后手动重试清除 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    var state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, isNotNull);

    fakeClient.enqueueChunks(['重试回复']);
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNull);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages.last.content, '重试回复');
  });

  test('handleStreamingFailure 空内容不设 emptyReplyAssistantId', () async {
    fakeClient.enqueueError(ChatCompletionException('模拟流式错误'));
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
    expect(state.activeConversation.messages.last.content, isEmpty);
  });

  test('stopStreaming 将 emptyReplyAssistantId 指向当前流式占位', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('开始流式');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 手动设置一个伪造的 emptyReplyAssistantId，模拟残留状态。
    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');
    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, 'test-id');

    await notifier.stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    // 流式未收到任何内容即被终止，emptyReplyAssistantId 被重置为当前
    // 流式占位节点 id，以便 UI 显示终止提示卡片与重试入口。
    final assistantId = state.streamingReply?.assistantMessageId ??
        state.activeConversation.messages
            .lastWhere((m) => m.role == ChatMessageRole.assistant)
            .id;
    expect(state.emptyReplyAssistantId, assistantId);
    expect(state.isStreaming, isFalse);
  });

  test('createConversation 清除 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('先发消息');

    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');
    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, 'test-id');

    await notifier.createConversation();

    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, isNull);
  });

  test('deleteConversations 清除 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['回复1']);
    fakeClient.enqueueChunks(['回复2']);
    await sendMsg('消息1');

    await container.read(chatSessionsProvider.notifier).createConversation();
    await sendMsg('消息2');

    var state = container.read(chatSessionsProvider);
    expect(state.conversations.length, 2);

    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');

    final activeId = state.activeConversationId;
    await notifier.deleteConversations({activeId});

    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, isNull);
  });

  test('空回复时 errorMessageAssistantId 不会被清除', () async {
    // 先模拟错误 → errorMessageAssistantId 设置，emptyReplyAssistantId 为空
    fakeClient.enqueueError(ChatCompletionException('模拟错误'));
    await sendMsg('触发错误');

    var state = container.read(chatSessionsProvider);
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);

    // 再模拟空回复 → emptyReplyAssistantId 设置，errorMessageAssistantId 被清除
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessageAssistantId, isNotNull);
  });

  test('连续两次空回不会残留前一次的 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['']); // 第一次空回复
    await sendMsg('第一条');

    var state = container.read(chatSessionsProvider);
    final firstId = state.emptyReplyAssistantId;
    expect(firstId, isNotNull);

    fakeClient.enqueueChunks(['']); // 第二次空回复
    await sendMsg('第二条');

    state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNot(firstId));
  });

  test('HTTP 429 错误显示为错误消息而非空回复', () async {
    fakeClient.enqueueError(
      ChatCompletionException('请求失败（429）：rate limit exceeded'),
    );
    await sendMsg('触发 429 错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, contains('429'));
    expect(state.errorMessage, contains('rate limit exceeded'));
    expect(state.errorMessageAssistantId, isNotNull);
    expect(state.emptyReplyAssistantId, isNull);
  });

  test('真正空回复仍走 emptyReplyAssistantId 路径', () async {
    fakeClient.enqueueChunks(['']);
    await sendMsg('触发空回复');

    final state = container.read(chatSessionsProvider);
    expect(state.emptyReplyAssistantId, isNotNull);
    expect(state.errorMessage, contains('模型返回了空回复'));
  });

  test('fixedInterval 模式首次失败后重试成功', () async {
    // 切换到固定间隔模式
    await container.read(autoRetrySettingsProvider.notifier).save(
      const AutoRetrySettings(retryMode: RetryMode.fixedInterval),
    );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatCompletionException('连接超时'));
    fakeClient.enqueueChunks(['固定间隔重试成功']);

    await sendMsg('测试固定间隔重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '固定间隔重试成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
  });

  test('fixedInterval 模式连续失败后第三次成功', () async {
    await container.read(autoRetrySettingsProvider.notifier).save(
      const AutoRetrySettings(retryMode: RetryMode.fixedInterval),
    );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: true);
    fakeClient.enqueueError(ChatCompletionException('第一次失败'));
    fakeClient.enqueueError(ChatCompletionException('第二次失败'));
    fakeClient.enqueueChunks(['第三次成功']);

    await sendMsg('固定间隔多次重试', retryDelay: Duration.zero);

    final state = container.read(chatSessionsProvider);
    expect(state.activeConversation.messages.last.content, '第三次成功');
    expect(state.errorMessage, isNull);
    expect(state.autoRetryCount, 0);
    expect(fakeClient.requestHistory.length, 3);
  });

  // ── stopStreaming 竞态条件 ──────────────────────────────────────────────

  test('stopStreaming 后延迟到达的 onDone 不改变状态', () async {
    // 使用 StreamController 模拟可控的流式生命周期
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试 onDone 竞态');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 终止流式
    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final stateAfterStop = container.read(chatSessionsProvider);
    expect(stateAfterStop.isStreaming, isFalse);
    final contentAfterStop = stateAfterStop.activeConversation.messages.last.content;

    // 模拟延迟到达的 onDone：关闭流控制器（触发 Stream onDone）
    streamController.add(const ChatCompletionChunk(contentDelta: '延迟内容'));
    await streamController.close();
    // 让微任务队列执行
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final stateAfterDelayed = container.read(chatSessionsProvider);
    expect(stateAfterDelayed.isStreaming, isFalse);
    // 延迟到达的 chunk 不应改变已有内容
    expect(
      stateAfterDelayed.activeConversation.messages.last.content,
      contentAfterStop,
    );
  });

  test('stopStreaming 后延迟到达的 onError 不改变状态', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试 onError 竞态');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '已有内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final stateAfterStop = container.read(chatSessionsProvider);
    expect(stateAfterStop.isStreaming, isFalse);
    final errorMessageAfterStop = stateAfterStop.errorMessage;

    // 模拟延迟到达的 onError
    streamController.addError(Exception('延迟错误'));
    await streamController.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final stateAfterDelayed = container.read(chatSessionsProvider);
    expect(stateAfterDelayed.isStreaming, isFalse);
    // 延迟到达的错误不应覆盖 stopStreaming 设置的 errorMessage
    expect(stateAfterDelayed.errorMessage, errorMessageAfterStop);
  });

  test('stopStreaming 后 streamStopRequested 保持 true 直到下次流式开始', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试标志保持');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    // stopStreaming 后 streamStopRequested 应保持 true
    // （不在 clearActiveStreamingSession 中重置）
    final notifier = container.read(chatSessionsProvider.notifier);
    expect(notifier.streamStopRequested, isTrue);

    // 开始新一轮流式时应重置为 false
    fakeClient.enqueueChunks(['新回复']);
    await sendMsg('新消息');

    expect(notifier.streamStopRequested, isFalse);
    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages.last.content, '新回复');
  });

  test('连续两次 stopStreaming 不产生异常', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试双击停止');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    // 立即再次调用 stopStreaming（模拟用户快速双击）
    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.activeConversation.messages.last.content, '部分内容');
  });

  test('stopStreaming 在 cancel() 挂起时仍能一次终止', () async {
    // 模拟 token 空闲间隙：底层订阅的 cancel() 永不完成（socket 无数据）。
    // 修复前 stopStreaming 会 await 该 cancel 而永久挂起，状态无法重置，
    // 需第二次点击才生效；修复后 cancel 即发即忘，单次调用即可终止。
    final streamController = StreamController<ChatCompletionChunk>(
      onCancel: () => Completer<void>().future,
    );
    addTearDown(() => streamController.onCancel = null);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('测试挂起 cancel');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    streamController.add(const ChatCompletionChunk(contentDelta: '部分内容'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // 用 timeout 作为快速失败守卫：修复前 stopStreaming 会 await 挂起的 cancel
    // 而永不返回，2 秒内即报 TimeoutException；修复后单次调用瞬间完成，不会真等 2 秒。
    await container
        .read(chatSessionsProvider.notifier)
        .stopStreaming()
        .timeout(const Duration(seconds: 2));
    await sendFuture;

    final state = container.read(chatSessionsProvider);
    expect(state.isStreaming, isFalse);
    expect(state.activeConversation.messages.last.content, '部分内容');
  });
}
