import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import '../../../helpers/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

void registerChatScreenBranchingTests() {
  testWidgets(
    'chat screen edits user message and regenerates following replies',
    (tester) async {
      final fakeClient = FakeChatCompletionClient()
        ..enqueueChunks(['原始回复一'])
        ..enqueueChunks(['原始回复二'])
        ..enqueueChunks(['原始回复三']);

      await pumpChatScreen(tester, fakeClient: fakeClient);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );

      await sendMessage(tester, '第一条原始问题');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '编辑重算用例首轮生成完成',
      );
      await sendMessage(tester, '第二条问题');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '编辑重算用例第二轮生成完成',
      );
      await sendMessage(tester, '第三条问题');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '编辑重算用例第三轮生成完成',
      );

      fakeClient.enqueueChunks(['重算后的第二条回复']);
      final activeConversation = container
          .read(chatSessionsProvider)
          .activeConversation;
      final secondUserMessage = activeConversation.messages
          .where((message) {
            return message.role == ChatMessageRole.user;
          })
          .elementAt(1);

      await container
          .read(chatSessionsProvider.notifier)
          .editMessage(
            messageId: secondUserMessage.id,
            nextContent: '第二条已修改问题',
          );
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '编辑消息后重算生成完成',
      );

      expect(find.textContaining('第一条原始问题'), findsWidgets);
      expect(find.textContaining('原始回复一'), findsWidgets);
      expect(find.textContaining('第二条已修改问题'), findsWidgets);
      expect(find.textContaining('重算后的第二条回复'), findsWidgets);
      expect(find.textContaining('原始回复二'), findsNothing);
      expect(find.textContaining('第三条问题'), findsNothing);
      expect(find.textContaining('原始回复三'), findsNothing);
      expect(
        fakeClient.requestHistory.last
            .map((message) => message.content)
            .toList(),
        ['第一条原始问题', '原始回复一', '第二条已修改问题'],
      );
    },
  );

  testWidgets('chat screen retries latest assistant reply', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复'])
      ..enqueueChunks(['重试后的回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '帮我重试一下');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '重试用例首轮生成完成',
    );

    await tester.tap(find.byTooltip('重试回复'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '重试后生成完成',
    );

    expect(find.textContaining('重试后的回复'), findsWidgets);
    expect(find.textContaining('原始回复'), findsNothing);
    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['帮我重试一下'],
    );
  });

  testWidgets('retry keeps assistant sibling versions in tree', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['重试后回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '测试重试分支');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '保留兄弟版本用例首轮生成完成',
    );

    await tester.tap(find.byTooltip('重试回复'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '保留兄弟版本用例重试生成完成',
    );
    final activeConversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    final rootUser = activeConversation.messageNodes.firstWhere((message) {
      return message.role == ChatMessageRole.user &&
          (message.parentId ?? rootConversationParentId) ==
              rootConversationParentId;
    });
    final assistantSiblings = activeConversation.messageNodes
        .where((message) {
          return message.role == ChatMessageRole.assistant &&
              message.parentId == rootUser.id;
        })
        .toList(growable: false);

    expect(assistantSiblings.length, 2);
    expect(find.textContaining('重试后回复'), findsWidgets);
    expect(find.text('2/2'), findsOneWidget);

    await container
        .read(chatSessionsProvider.notifier)
        .selectMessageVersion(
          parentId: rootUser.id,
          messageId: assistantSiblings.first.id,
        );
    // 树版本切换是同步状态变更，单帧渲染即可。
    await tester.pump();

    expect(find.textContaining('首次回复'), findsWidgets);
  });

  testWidgets(
    'failed request shows inline error bubble and retries without 2/2',
    (tester) async {
      final fakeClient = FakeChatCompletionClient()
        ..enqueueError(ChatCompletionException('HTTP 503: unavailable'))
        ..enqueueChunks(['重试恢复成功']);

      await pumpChatScreen(tester, fakeClient: fakeClient);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );

      await sendMessage(tester, '先触发一次错误');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.failed,
        description: '错误请求进入失败终态',
      );

      expect(find.textContaining('HTTP 503: unavailable'), findsWidgets);
      expect(find.text('2/2'), findsNothing);

      await tester.tap(find.byTooltip('重试回复').last);
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '错误恢复重试生成完成',
      );

      expect(find.textContaining('重试恢复成功'), findsWidgets);
      expect(find.text('2/2'), findsNothing);
    },
  );

  testWidgets('editing user message creates switchable root branches', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复一'])
      ..enqueueChunks(['原始回复二'])
      ..enqueueChunks(['编辑后回复一']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '原始用户1');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '根分支用例首轮生成完成',
    );
    await sendMessage(tester, '原始用户2');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '根分支用例第二轮生成完成',
    );
    final beforeEditConversation = container
        .read(chatSessionsProvider)
        .activeConversation;
    final originalRootUser = beforeEditConversation.messageNodes.firstWhere((
      message,
    ) {
      return message.role == ChatMessageRole.user &&
          (message.parentId ?? rootConversationParentId) ==
              rootConversationParentId;
    });

    await container
        .read(chatSessionsProvider.notifier)
        .editMessage(messageId: originalRootUser.id, nextContent: '编辑后的用户1');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '根分支编辑后重算完成',
    );

    expect(find.textContaining('编辑后的用户1'), findsWidgets);
    expect(find.textContaining('编辑后回复一'), findsWidgets);
    expect(find.textContaining('原始用户2'), findsNothing);
    expect(find.text('2/2'), findsOneWidget);

    await container
        .read(chatSessionsProvider.notifier)
        .selectMessageVersion(
          parentId: rootConversationParentId,
          messageId: originalRootUser.id,
        );
    // 树版本切换是同步状态变更，单帧渲染即可。
    await tester.pump();

    expect(find.textContaining('原始用户1'), findsWidgets);
    expect(find.textContaining('原始用户2'), findsWidgets);
    expect(find.textContaining('原始回复二'), findsWidgets);
  });

  // ── 删除分支测试共享 setup ──────────────────

  /// 创建一个有 2 个版本 assistant 回复的对话供删除测试使用
  Future<void> setupDeleteScenario(WidgetTester tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['重试后回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await sendMessage(tester, '测试删除弹窗');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '删除场景首轮生成完成',
    );
    await tester.tap(find.byTooltip('重试回复'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '删除场景重试生成完成',
    );
  }

  testWidgets('delete message dialog offers current branch or all versions', (
    tester,
  ) async {
    await setupDeleteScenario(tester);

    await tester.tap(find.byTooltip('删除消息').last);
    await settleOverlayTransition(tester);

    expect(find.text('删除哪个范围？'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '删除当前分支'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '删除全部版本'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除当前分支'));
    await settleOverlayTransition(tester);

    expect(find.textContaining('首次回复'), findsWidgets);
    expect(find.textContaining('重试后回复'), findsNothing);
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('delete all assistant versions removes the reply node', (
    tester,
  ) async {
    await setupDeleteScenario(tester);

    await tester.tap(find.byTooltip('删除消息').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除全部版本'));
    await settleOverlayTransition(tester);

    expect(find.textContaining('首次回复'), findsNothing);
    expect(find.textContaining('重试后回复'), findsNothing);
    expect(find.textContaining('测试删除弹窗'), findsWidgets);
  });

  testWidgets('空回复时渲染 ChatInlineEmptyReplyCard 而非 ChatInlineErrorCard', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()
      // 空字符串 chunk 触发空回复路径（anyChunkYielded=true + content 为空）
      ..enqueueChunks(['']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '触发空回复');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.emptyReply,
      description: '空回复进入空回复终态',
    );

    expect(find.textContaining(ChatErrorMessages.emptyReply), findsOneWidget);
  });

  testWidgets('真实错误时渲染 ChatInlineErrorCard 而非 ChatInlineEmptyReplyCard', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueError(ChatCompletionException('测试网络错误'));

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '触发错误');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.failed,
      description: '真实错误进入失败终态',
    );

    expect(find.textContaining('测试网络错误'), findsOneWidget);
    expect(find.textContaining(ChatErrorMessages.emptyReply), findsNothing);
  });
}
