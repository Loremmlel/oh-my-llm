/// 消息版本导航持久化集成测试。
///
/// 验证 selectedChildByParentId 在容器重建后的序列化/反序列化正确性：
/// 编辑用户消息创建分支 -> 切换回旧分支 -> 重启 -> 验证选中的仍是旧分支。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/domain/chat_message_parent.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 编辑后切换回旧版本 -> 重启 -> 旧版本仍被选中 ──────────────────────────────

  test('编辑后切换回旧版本 -> 重启后旧版本仍被选中', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(database.close);

    // 第一轮对话
    fakeClient.enqueueChunks(['原始回复']);
    await sendMsg(containerA, content: '原始问题');

    final stateA = containerA.read(chatSessionsProvider);
    final userMessageId = stateA.activeConversation.messages
        .firstWhere((m) => m.role == ChatMessageRole.user)
        .id;
    final originalAssistantId = stateA.activeConversation.messages
        .firstWhere((m) => m.role == ChatMessageRole.assistant)
        .id;
    final userMessage = stateA.activeConversation.messages
        .firstWhere((m) => m.id == userMessageId);
    final parentId = userMessage.effectiveParentId;

    // 编辑用户消息，创建新分支
    fakeClient.enqueueChunks(['编辑后的回复']);
    await containerA.read(chatSessionsProvider.notifier).editMessage(
          messageId: userMessageId,
          nextContent: '修改后的问题',
        );

    // 验证新分支被选中
    final messagesAfterEdit = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesAfterEdit[0].content, '修改后的问题');
    expect(messagesAfterEdit[1].content, '编辑后的回复');

    // 切换回旧版本
    containerA.read(chatSessionsProvider.notifier).selectMessageVersion(
          parentId: parentId,
          messageId: userMessageId,
        );

    // 验证旧版本被选中
    final messagesAfterSwitch = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesAfterSwitch[0].content, '原始问题');
    expect(messagesAfterSwitch[1].content, '原始回复');

    containerA.dispose();

    // 模拟重启
    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
    );
    addTearDown(containerB.dispose);

    // 验证旧版本仍然被选中
    final messagesB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB[0].content, '原始问题');
    expect(messagesB[1].content, '原始回复');
    expect(messagesB[1].id, originalAssistantId);
  });

  // ── 编辑后新分支被选中 -> 重启 -> 新分支仍被选中 ──────────────────────────────

  test('编辑后新分支被选中 -> 重启后新分支仍被选中', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(database.close);

    fakeClient.enqueueChunks(['原始回复']);
    await sendMsg(containerA, content: '原始问题');

    final stateA = containerA.read(chatSessionsProvider);
    final userMessageId = stateA.activeConversation.messages
        .firstWhere((m) => m.role == ChatMessageRole.user)
        .id;

    // 编辑创建新分支
    fakeClient.enqueueChunks(['新分支回复']);
    await containerA.read(chatSessionsProvider.notifier).editMessage(
          messageId: userMessageId,
          nextContent: '编辑后的问题',
        );

    // 验证新分支被选中
    final messagesAfterEdit = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesAfterEdit[0].content, '编辑后的问题');
    expect(messagesAfterEdit[1].content, '新分支回复');

    containerA.dispose();

    // 模拟重启
    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
      ],
    );
    addTearDown(containerB.dispose);

    // 验证新分支仍然被选中
    final messagesB = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB[0].content, '编辑后的问题');
    expect(messagesB[1].content, '新分支回复');
  });
}
