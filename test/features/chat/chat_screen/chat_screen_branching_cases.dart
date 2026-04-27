import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenBranchingTests() {
  testWidgets(
    'chat screen edits user message and regenerates following replies',
    (tester) async {
      final preferences = await createSeededPreferences();
      final fakeClient = FakeChatCompletionClient()
        ..enqueueChunks(['原始回复一'])
        ..enqueueChunks(['原始回复二'])
        ..enqueueChunks(['原始回复三']);

      await pumpChatScreen(
        tester,
        preferences: preferences,
        fakeClient: fakeClient,
      );

      await sendMessage(tester, '第一条原始问题');
      await tester.pumpAndSettle();
      await sendMessage(tester, '第二条问题');
      await tester.pumpAndSettle();
      await sendMessage(tester, '第三条问题');
      await tester.pumpAndSettle();

      fakeClient.enqueueChunks(['重算后的第二条回复']);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
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
      await tester.pumpAndSettle();

      expect(find.textContaining('第一条原始问题'), findsWidgets);
      expect(find.textContaining('原始回复一'), findsWidgets);
      expect(find.textContaining('第二条已修改问题'), findsWidgets);
      expect(find.textContaining('重算后的第二条回复'), findsWidgets);
      expect(find.textContaining('原始回复二'), findsNothing);
      expect(find.textContaining('第三条问题'), findsNothing);
      expect(find.textContaining('原始回复三'), findsNothing);
      expect(
        fakeClient.requestHistory[3].map((message) => message.content).toList(),
        ['第一条原始问题', '原始回复一', '第二条已修改问题'],
      );
    },
  );

  testWidgets('chat screen retries latest assistant reply', (tester) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复'])
      ..enqueueChunks(['重试后的回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '帮我重试一下');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重试回复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('重试后的回复'), findsWidgets);
    expect(find.textContaining('原始回复'), findsNothing);
    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['帮我重试一下'],
    );
  });

  testWidgets('retry keeps assistant sibling versions in tree', (tester) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['重试后回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '测试重试分支');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('重试回复'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
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
    await tester.pumpAndSettle();

    expect(find.textContaining('首次回复'), findsWidgets);
  });

  testWidgets('editing user message creates switchable root branches', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复一'])
      ..enqueueChunks(['原始回复二'])
      ..enqueueChunks(['编辑后回复一']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '原始用户1');
    await tester.pumpAndSettle();
    await sendMessage(tester, '原始用户2');
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.textContaining('原始用户1'), findsWidgets);
    expect(find.textContaining('原始用户2'), findsWidgets);
    expect(find.textContaining('原始回复二'), findsWidgets);
  });
}
