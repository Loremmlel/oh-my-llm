import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenStreamingTests() {
  testWidgets('chat screen streams reply and updates anchors/history', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    fakeClient.enqueueChunks([
      '第一段 ',
      '第二段',
    ], chunkDelay: const Duration(milliseconds: 10));

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await tester.enterText(find.byType(TextField), '帮我总结一下这个仓库的结构和当前能力');
    final sendButton = find.widgetWithText(FilledButton, '发送');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 12));

    expect(find.textContaining('第一段'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '终止回答'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.textContaining('帮我总结一下这个仓库'), findsWidgets);
    expect(find.textContaining('第一段 第二段'), findsWidgets);
    expect(find.textContaining('帮我总结一下这个仓'), findsWidgets);
    expect(find.byKey(const ValueKey('message-anchor-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-anchor-item-1')), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(
      fakeClient.lastRequestMessages.map((message) => message.role).toList(),
      [ChatMessageRole.user],
    );
    expect(fakeClient.lastRequestMessages.single.content, '帮我总结一下这个仓库的结构和当前能力');
    expect(fakeClient.lastModelConfig?.displayName, equals('GPT-4.1'));
  });

  testWidgets('chat screen shows reasoning in a collapsible panel', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueDeltas([
        const ChatCompletionChunk(reasoningDelta: '这是思考过程'),
        const ChatCompletionChunk(contentDelta: '这是最终回复'),
      ]);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '请回答并返回思考过程');
    await tester.pumpAndSettle();

    expect(find.text('展开'), findsOneWidget);
    expect(find.text('这是思考过程'), findsNothing);
    expect(find.textContaining('这是最终回复'), findsWidgets);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    expect(find.text('这是思考过程'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('chat screen copies raw message content without reasoning', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueDeltas([
        const ChatCompletionChunk(reasoningDelta: '这是思考过程'),
        const ChatCompletionChunk(contentDelta: '这是最终回复'),
      ]);
    String? clipboardText;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final arguments = methodCall.arguments as Map<dynamic, dynamic>;
              clipboardText = arguments['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }

          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '请原样复制这条用户消息');
    await tester.pumpAndSettle();

    expect(find.byTooltip('复制消息'), findsNWidgets(2));

    await tester.tap(find.byTooltip('复制消息').first);
    await tester.pumpAndSettle();

    expect(
      (await Clipboard.getData('text/plain'))?.text,
      equals('请原样复制这条用户消息'),
    );

    await tester.tap(find.byTooltip('复制消息').last);
    await tester.pumpAndSettle();

    expect((await Clipboard.getData('text/plain'))?.text, equals('这是最终回复'));
    expect((await Clipboard.getData('text/plain'))?.text, isNot('这是思考过程'));
  });

  testWidgets('chat screen keeps user message markdown syntax as raw text', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['收到']);
    const userMessage = '**保留原样**\n- 这不是列表';

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, userMessage);
    await tester.pumpAndSettle();

    expect(find.text(userMessage), findsOneWidget);
    expect(find.textContaining('收到'), findsWidgets);
  });

  testWidgets('chat screen shows a confirmation dialog before stopping', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    final streamController = StreamController<ChatCompletionChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '请开始长回复');
    await tester.pump();

    streamController.add(const ChatCompletionChunk(contentDelta: '已生成部分'));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.widgetWithText(FilledButton, '终止回答'));
    await tester.pump();
    expect(find.text('终止本次回答？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '继续生成'));
    await tester.pump();
    expect(find.text('终止本次回答？'), findsNothing);
    expect(find.widgetWithText(FilledButton, '终止回答'), findsOneWidget);
    expect(find.textContaining('已生成部分'), findsWidgets);
  });
}
