/// 多对话切换与重启恢复集成测试。
///
/// 验证多对话场景下的持久化与恢复：
/// 创建 A -> 发消息 -> 创建 B -> 发消息 -> 切换回 A -> 验证消息完整。
/// 以及容器重建后多对话列表与活动对话正确恢复。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../helpers/chat/fake_chat_generation_client.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 多对话重启后恢复 ──────────────────────────────────────────────────────────

  test('重启恢复活动对话和列表，切换时懒加载另一对话的完整消息', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClientA = FakeChatGenerationClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(fakeClientA),
        chatConversationRepositoryProvider.overrideWithValue(
          SqliteChatConversationRepository(database),
        ),
      ],
    );
    addTearDown(database.close);

    // 对话 A
    fakeClientA.enqueueChunks(['A 回复']);
    await sendMsg(containerA, content: 'A 消息');
    final conversationAId = containerA
        .read(chatSessionsProvider)
        .activeConversationId;

    // 创建对话 B
    await containerA.read(chatSessionsProvider.notifier).createConversation();
    fakeClientA.enqueueChunks(['B 回复']);
    await sendMsg(containerA, content: 'B 消息');

    final stateA = containerA.read(chatSessionsProvider);
    final conversationBId = stateA.activeConversationId;
    expect(conversationBId, isNot(conversationAId));

    containerA.dispose();

    // 模拟重启
    final containerB = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(
          FakeChatGenerationClient(),
        ),
        chatConversationRepositoryProvider.overrideWithValue(
          SqliteChatConversationRepository(database),
        ),
      ],
    );
    addTearDown(containerB.dispose);

    final stateB = containerB.read(chatSessionsProvider);
    expect(
      stateB.conversationSummaries.map((summary) => summary.id),
      unorderedEquals([conversationAId, conversationBId]),
    );
    expect(stateB.activeConversationId, conversationBId);
    expect(
      stateB.activeConversation.messages.map(
        (message) => (message.role, message.content),
      ),
      [(ChatMessageRole.user, 'B 消息'), (ChatMessageRole.assistant, 'B 回复')],
    );

    containerB
        .read(chatSessionsProvider.notifier)
        .selectConversation(conversationAId);

    final messages = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages.map((message) => (message.role, message.content)), [
      (ChatMessageRole.user, 'A 消息'),
      (ChatMessageRole.assistant, 'A 回复'),
    ]);
  });
}
