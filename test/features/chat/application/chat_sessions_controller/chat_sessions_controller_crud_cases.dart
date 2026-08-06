import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';

import '../../../../helpers/fake_chat_completion_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 会话 CRUD、preferences、historyRevision 与 emptyReplyAssistantId 边界契约。
void registerChatSessionsControllerCrudCases() {
  late ControllerTestHarness harness;
  late AppDatabase database;
  late SharedPreferences preferences;
  late FakeChatCompletionClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    harness = ControllerTestHarness();
    await harness.init();
    database = harness.database;
    preferences = harness.preferences;
    fakeClient = harness.fakeClient;
    container = harness.container;
  });
  tearDown(() => harness.dispose());

  Future<void> sendMsg(String content, {Duration? retryDelay}) =>
      harness.sendMsg(content, retryDelay: retryDelay);

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
        chatConversationRepositoryProvider.overrideWithValue(
          SqliteChatConversationRepository(database),
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

  // ── setMessagesExcluded ────────────────────────────────────────────────────

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

  // ── emptyReplyAssistantId 边界 ──────────────────────────────────────────────

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
    expect(
      container.read(chatSessionsProvider).emptyReplyAssistantId,
      'test-id',
    );

    // 切换到第一个会话应清除 emptyReplyAssistantId
    notifier.selectConversation(firstId);
    expect(container.read(chatSessionsProvider).emptyReplyAssistantId, isNull);
  });

  test('createConversation 清除 emptyReplyAssistantId', () async {
    fakeClient.enqueueChunks(['回复']);
    await sendMsg('先发消息');

    final notifier = container.read(chatSessionsProvider.notifier);
    notifier.state = notifier.state.copyWith(emptyReplyAssistantId: 'test-id');
    expect(
      container.read(chatSessionsProvider).emptyReplyAssistantId,
      'test-id',
    );

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
}
