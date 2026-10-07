/// 消息版本导航持久化集成测试。
///
/// 验证 selectedChildByParentId 在容器重建后的序列化/反序列化正确性：
/// 编辑后重启保留新分支，再切换旧分支并重启保留旧分支与图片。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/chat_message_parent.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../helpers/chat/fake_chat_generation_client.dart';
import '../helpers/integration_test_helpers.dart';
import '../helpers/chat/test_chat_images.dart';

void main() {
  test('新旧消息版本的选中状态与图片均可在重启后恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatGenerationClient();

    final containerA = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: fakeClient,
    );
    addTearDown(database.close);

    // 第一轮对话
    fakeClient.enqueueChunks(['原始回复']);
    await sendMsg(containerA, content: '原始问题', images: [testChatImage]);

    final stateA = containerA.read(chatSessionsProvider);
    final userMessageId = stateA.activeConversation.messages
        .firstWhere((m) => m.role == ChatMessageRole.user)
        .id;
    final originalAssistantId = stateA.activeConversation.messages
        .firstWhere((m) => m.role == ChatMessageRole.assistant)
        .id;
    final userMessage = stateA.activeConversation.messages.firstWhere(
      (m) => m.id == userMessageId,
    );
    final parentId = userMessage.effectiveParentId;

    // 编辑用户消息，创建新分支
    fakeClient.enqueueChunks(['编辑后的回复']);
    await containerA
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: userMessageId, nextContent: '修改后的问题');

    // 验证新分支被选中
    final messagesAfterEdit = containerA
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesAfterEdit[0].content, '修改后的问题');
    expect(messagesAfterEdit[0].images, [testChatImage]);
    expect(messagesAfterEdit[1].content, '编辑后的回复');
    containerA.dispose();

    final containerB = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    final restoredNewBranch = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(restoredNewBranch, messagesAfterEdit);

    // 切换回旧版本
    containerB
        .read(chatSessionsProvider.notifier)
        .selectMessageVersion(parentId: parentId, messageId: userMessageId);

    // 验证旧版本被选中
    final messagesAfterSwitch = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesAfterSwitch[0].content, '原始问题');
    expect(messagesAfterSwitch[1].content, '原始回复');

    containerB.dispose();

    // 模拟重启
    final containerC = createTestContainer(
      database: database,
      preferences: preferences,
      fakeClient: FakeChatGenerationClient(),
    );
    addTearDown(containerC.dispose);

    // 验证旧版本仍然被选中
    final messagesB = containerC
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messagesB[0].content, '原始问题');
    expect(messagesB[0].images, [testChatImage]);
    expect(messagesB[1].content, '原始回复');
    expect(messagesB[1].id, originalAssistantId);
  });
}
