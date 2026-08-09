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
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 多对话重启后恢复 ──────────────────────────────────────────────────────────

  test('多对话容器重建 - 对话列表和活动对话恢复', () async {
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

    // 创建对话 B
    await containerA.read(chatSessionsProvider.notifier).createConversation();
    fakeClientA.enqueueChunks(['B 回复']);
    await sendMsg(containerA, content: 'B 消息');

    final stateA = containerA.read(chatSessionsProvider);
    expect(stateA.conversationSummaries.length, greaterThanOrEqualTo(2));

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
    // 对话列表恢复
    expect(stateB.conversationSummaries.length, greaterThanOrEqualTo(2));
    // 活动对话被加载
    expect(stateB.activeConversation, isNotNull);
    expect(stateB.activeConversation.messages, isNotEmpty);
  });

  // ── 切换到未加载的对话后重启 - 懒加载恢复 ──────────────────────────────────────

  test('切换到未加载的对话后重启 - 该对话可懒加载恢复', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatGenerationClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatGenerationClientProvider.overrideWithValue(fakeClient),
        chatConversationRepositoryProvider.overrideWithValue(
          SqliteChatConversationRepository(database),
        ),
      ],
    );
    addTearDown(database.close);

    // 对话 A 发消息
    fakeClient.enqueueChunks(['A 回复']);
    await sendMsg(containerA, content: 'A 消息');

    final conversationAId = containerA
        .read(chatSessionsProvider)
        .activeConversationId;

    // 创建对话 B 并发消息
    await containerA.read(chatSessionsProvider.notifier).createConversation();
    fakeClient.enqueueChunks(['B 回复']);
    await sendMsg(containerA, content: 'B 消息');

    final conversationBId = containerA
        .read(chatSessionsProvider)
        .activeConversationId;

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

    // 切换到另一个对话（触发懒加载）
    final activeId = containerB.read(chatSessionsProvider).activeConversationId;
    final targetId = activeId == conversationAId
        ? conversationBId
        : conversationAId;

    containerB.read(chatSessionsProvider.notifier).selectConversation(targetId);

    final messages = containerB
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages, isNotEmpty);
    expect(messages.any((m) => m.role == ChatMessageRole.user), isTrue);
  });
}
