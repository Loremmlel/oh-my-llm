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
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../features/chat/chat_screen/chat_screen_test_helpers.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  // ── 多对话切换不串数据 ────────────────────────────────────────────────────────

  test('创建多对话后切换 - 各对话消息独立', () async {
    final database = AppDatabase.inMemory();
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(database.close);
    addTearDown(container.dispose);

    // 对话 A：发两条消息
    fakeClient.enqueueChunks(['A 的第一条回复']);
    await sendMsg(container, content: 'A1');
    fakeClient.enqueueChunks(['A 的第二条回复']);
    await sendMsg(container, content: 'A2');

    final conversationAId =
        container.read(chatSessionsProvider).activeConversationId;

    // 创建对话 B
    await container.read(chatSessionsProvider.notifier).createConversation();
    final conversationBId =
        container.read(chatSessionsProvider).activeConversationId;
    expect(conversationBId, isNot(equals(conversationAId)));

    // 对话 B：发一条消息
    fakeClient.enqueueChunks(['B 的回复']);
    await sendMsg(container, content: 'B1');

    // 验证 B 有 2 条消息（1 user + 1 assistant）
    final messagesB =
        container.read(chatSessionsProvider).activeConversation.messages;
    expect(messagesB.length, 2);
    expect(messagesB[0].content, 'B1');
    expect(messagesB[1].content, 'B 的回复');

    // 切换回 A
    container.read(chatSessionsProvider.notifier).selectConversation(conversationAId);

    // 验证 A 有 4 条消息（2 user + 2 assistant）
    final messagesA =
        container.read(chatSessionsProvider).activeConversation.messages;
    expect(messagesA.length, 4);
    expect(messagesA[0].content, 'A1');
    expect(messagesA[1].content, 'A 的第一条回复');
    expect(messagesA[2].content, 'A2');
    expect(messagesA[3].content, 'A 的第二条回复');
  });

  // ── 多对话重启后恢复 ──────────────────────────────────────────────────────────

  test('多对话容器重建 - 对话列表和活动对话恢复', () async {
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
        chatCompletionClientProvider.overrideWithValue(FakeChatCompletionClient()),
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
    final fakeClient = FakeChatCompletionClient();

    final containerA = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
    addTearDown(database.close);

    // 对话 A 发消息
    fakeClient.enqueueChunks(['A 回复']);
    await sendMsg(containerA, content: 'A 消息');

    final conversationAId =
        containerA.read(chatSessionsProvider).activeConversationId;

    // 创建对话 B 并发消息
    await containerA.read(chatSessionsProvider.notifier).createConversation();
    fakeClient.enqueueChunks(['B 回复']);
    await sendMsg(containerA, content: 'B 消息');

    final conversationBId =
        containerA.read(chatSessionsProvider).activeConversationId;

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

    // 切换到另一个对话（触发懒加载）
    final activeId =
        containerB.read(chatSessionsProvider).activeConversationId;
    final targetId =
        activeId == conversationAId ? conversationBId : conversationAId;

    containerB.read(chatSessionsProvider.notifier).selectConversation(targetId);

    final messages =
        containerB.read(chatSessionsProvider).activeConversation.messages;
    expect(messages, isNotEmpty);
    expect(
      messages.any((m) => m.role == ChatMessageRole.user),
      isTrue,
    );
  });
}
