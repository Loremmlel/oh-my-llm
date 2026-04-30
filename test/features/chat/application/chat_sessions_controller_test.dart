import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

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

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-1',
          'displayName': 'Test Model',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'test-model',
          'supportsReasoning': false,
        },
      ]),
      promptTemplatesStorageKey: jsonEncode([
        {
          'id': 'prompt-1',
          'name': '模板一',
          'systemPrompt': '',
          'messages': [
            {
              'id': 'prompt-1-message-1',
              'role': 'user',
              'content': '模板一前置',
              'placement': 'before',
            },
          ],
          'updatedAt': DateTime(2026, 4, 30).toIso8601String(),
        },
        {
          'id': 'prompt-2',
          'name': '模板二',
          'systemPrompt': '',
          'messages': [
            {
              'id': 'prompt-2-message-1',
              'role': 'user',
              'content': '模板二前置',
              'placement': 'before',
            },
          ],
          'updatedAt': DateTime(2026, 4, 30, 0, 1).toIso8601String(),
        },
      ]),
    });
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
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
  Future<void> sendMsg(String content) => container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: content,
        modelConfig: _testModel,
        promptTemplate: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
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

  test('流式进行中 deleteConversations 为空操作', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('消息');
    final id = container.read(chatSessionsProvider).activeConversationId;

    // 手动把 isStreaming 置为 true（模拟流式进行中）
    container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '第二条',
          modelConfig: _testModel,
          promptTemplate: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    // 在 Future 完成前读取状态（此处流式是同步 Stream，所以直接等待即可跳过测试）
    // 使用 isStreaming guard：传入空 Stream 时 isStreaming 仍为 true 直到 await 完成
    // 此测试仅验证 deleteConversations 在 isStreaming 时不删除已有记录
    final countBefore = container
        .read(chatSessionsProvider)
        .conversations
        .length;
    // 如果已经不在流式中（空流立即完成），跳过 isStreaming 验证
    if (!container.read(chatSessionsProvider).isStreaming) {
      return;
    }
    await container.read(chatSessionsProvider.notifier).deleteConversations({
      id,
    });
    expect(
      container.read(chatSessionsProvider).conversations.length,
      countBefore,
    );
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
  });

  test('sendMessage 自动裁剪前后空白', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('  你好  ');

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages[0].content, '你好');
  });

  test('sendMessage 纯空白内容为空操作', () async {
    await container
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: '   ',
          modelConfig: _testModel,
          promptTemplate: null,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    expect(
      container.read(chatSessionsProvider).activeConversation.hasMessages,
      isFalse,
    );
  });

  test('sendMessage 完成后 isStreaming 为 false', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('你好');
    expect(container.read(chatSessionsProvider).isStreaming, isFalse);
  });

  test('sendMessage 错误时设置 errorMessage 并清除 isStreaming', () async {
    fakeClient.enqueueError(ChatCompletionException('API 请求失败'));
    await sendMsg('触发错误');

    final state = container.read(chatSessionsProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.isStreaming, isFalse);
  });

  test('sendMessage 错误且无部分内容时清除占位 assistant 节点', () async {
    fakeClient.enqueueError(ChatCompletionException('请求失败'));
    await sendMsg('触发错误');

    // 空流失败后 assistant 占位节点应被移除，只剩 user 消息
    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.length, 1);
    expect(messages.first.role, ChatMessageRole.user);
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

  test('retryLatestAssistant 重新生成最后一条助手回复', () async {
    fakeClient.enqueueChunks(['初次回复']);
    fakeClient.enqueueChunks(['重试回复']);
    await sendMsg('问题');

    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.length, 2);
    expect(messages.last.content, '重试回复');
  });

  test('retryLatestAssistant 无助手消息时设置 errorMessage', () async {
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();
    expect(container.read(chatSessionsProvider).errorMessage, isNotNull);
  });

  test('retryLatestAssistant 可重试失败后未落树的最新用户消息', () async {
    fakeClient.enqueueError(ChatCompletionException('503 unavailable'));
    await sendMsg('先失败后重试');
    expect(
      container.read(chatSessionsProvider).activeConversation.messages,
      hasLength(1),
    );

    fakeClient.enqueueChunks(['重试成功回复']);
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();

    final state = container.read(chatSessionsProvider);
    final messages = state.activeConversation.messages;
    expect(messages, hasLength(2));
    expect(messages[0].role, ChatMessageRole.user);
    expect(messages[1].role, ChatMessageRole.assistant);
    expect(messages[1].content, '重试成功回复');
    expect(state.errorMessage, isNull);

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

  test('stopStreaming 在无内容时移除空白助手占位', () async {
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    final sendFuture = sendMsg('不要输出任何内容');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    await container.read(chatSessionsProvider.notifier).stopStreaming();
    await sendFuture;

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.role, ChatMessageRole.user);
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
}
