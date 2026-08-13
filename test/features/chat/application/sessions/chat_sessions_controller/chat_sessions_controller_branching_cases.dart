import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../../../../helpers/fake_chat_generation_client.dart';
import 'chat_sessions_controller_test_helpers.dart';

/// 编辑用户消息产生新分支、retry、deleteMessage 版本导航契约。
void registerChatSessionsControllerBranchingCases() {
  late ControllerTestHarness harness;
  late FakeChatGenerationClient fakeClient;
  late ProviderContainer container;

  setUp(() async {
    harness = ControllerTestHarness();
    await harness.init();
    fakeClient = harness.fakeClient;
    container = harness.container;
  });
  tearDown(() => harness.dispose());

  Future<void> sendMsg(String content, {Duration? retryDelay}) =>
      harness.sendMsg(content, retryDelay: retryDelay);

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

  test('editMessage 新分支消息携带模板元数据', () async {
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
        .editMessage(
          messageId: userMessageId,
          nextContent: '修改后的问题',
          userMessageSegments: [
            const UserMessageSegment(
              text: '修改后的问题',
              kind: UserMessageSegmentKind.body,
            ),
          ],
          templatePromptId: 'tpl-1',
          templateVariableValues: {'lang': 'Dart'},
        );

    final messages = container
        .read(chatSessionsProvider)
        .activeConversation
        .messages;
    expect(messages[0].templatePromptId, 'tpl-1');
    expect(messages[0].templateVariableValues, {'lang': 'Dart'});
    expect(messages[0].userMessageSegments, hasLength(1));
    expect(
      messages[0].userMessageSegments.first.kind,
      UserMessageSegmentKind.body,
    );
  });

  test('editMessage 默认不携带模板元数据（向后兼容）', () async {
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
    expect(messages[0].templatePromptId, isNull);
    expect(messages[0].templateVariableValues, isEmpty);
    expect(messages[0].userMessageSegments, isEmpty);
  });

  // ── retryLatestAssistant ───────────────────────────────────────────────────

  test('retryLatestAssistant 无助手消息时设置 errorMessage', () async {
    await container.read(chatSessionsProvider.notifier).retryLatestAssistant();
    expect(container.read(chatSessionsProvider).errorMessage, isNotNull);
  });

  test('retryLatestAssistant 可重试失败后的最新助手消息', () async {
    fakeClient.enqueueError(ChatGenerationException('503 unavailable'));
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

  // ── deleteMessage ───────────────────────────────────────────────────────────

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

  // ── selectConversationAndNavigateToMessage ────────────────────────────────

  group('selectConversationAndNavigateToMessage', () {
    test('messageId 为 null 时退化为普通 selectConversation', () {
      final controller = container.read(chatSessionsProvider.notifier);
      final state = container.read(chatSessionsProvider);
      final convId = state.activeConversationId;

      controller.selectConversationAndNavigateToMessage(convId);

      final afterState = container.read(chatSessionsProvider);
      expect(afterState.activeConversationId, convId);
      expect(afterState.pendingScrollToMessageId, isNull);
    });

    test('目标消息在线性路径上时设置 pendingScrollToMessageId', () async {
      fakeClient.enqueueChunks(['你好！']);
      await sendMsg('你好');

      final controller = container.read(chatSessionsProvider.notifier);
      final state = container.read(chatSessionsProvider);
      final conv = state.activeConversation;
      final assistantMsg = conv.messages.lastWhere(
        (m) => m.role == ChatMessageRole.assistant,
      );

      controller.selectConversationAndNavigateToMessage(
        conv.id,
        messageId: assistantMsg.id,
      );

      final afterState = container.read(chatSessionsProvider);
      expect(afterState.pendingScrollToMessageId, assistantMsg.id);
    });

    test('目标消息在另一分支时 selectedChildByParentId 切换到正确分支', () async {
      fakeClient.enqueueChunks(['第一轮回复']);
      await sendMsg('第一轮');

      final controller = container.read(chatSessionsProvider.notifier);
      var conv = container.read(chatSessionsProvider).activeConversation;

      final firstUserMsg = conv.messages.firstWhere(
        (m) => m.role == ChatMessageRole.user,
      );

      final branchUserMsg = ChatMessage(
        id: 'branch-user-1',
        role: ChatMessageRole.user,
        content: '分支问题',
        parentId: firstUserMsg.parentId,
        createdAt: DateTime.now(),
      );
      final branchAssistantMsg = ChatMessage(
        id: 'branch-assistant-1',
        role: ChatMessageRole.assistant,
        content: '分支回复',
        parentId: branchUserMsg.id,
        createdAt: DateTime.now(),
        assistantModelDisplayName: 'Test Model',
      );

      conv = conv.copyWith(
        messageNodes: [...conv.messageNodes, branchUserMsg, branchAssistantMsg],
      );
      controller.updateActiveConversation(conv);

      expect(
        conv.messages.where((m) => m.id == branchAssistantMsg.id),
        isEmpty,
      );

      controller.selectConversationAndNavigateToMessage(
        conv.id,
        messageId: branchAssistantMsg.id,
      );

      final afterState = container.read(chatSessionsProvider);
      expect(afterState.pendingScrollToMessageId, branchAssistantMsg.id);

      final afterConv = afterState.activeConversation;
      expect(
        afterConv.messages.where((m) => m.id == branchAssistantMsg.id),
        isNotEmpty,
      );
    });

    test('目标消息不在 messageNodes 中时不修改状态', () async {
      fakeClient.enqueueChunks(['回复']);
      await sendMsg('测试消息');

      final controller = container.read(chatSessionsProvider.notifier);
      final stateBefore = container.read(chatSessionsProvider);
      final convId = stateBefore.activeConversationId;
      final selectionsBefore =
          stateBefore.activeConversation.selectedChildByParentId;

      controller.selectConversationAndNavigateToMessage(
        convId,
        messageId: 'nonexistent-message-id',
      );

      final stateAfter = container.read(chatSessionsProvider);
      expect(stateAfter.pendingScrollToMessageId, isNull);
      expect(
        stateAfter.activeConversation.selectedChildByParentId,
        selectionsBefore,
      );
    });
  });
}
