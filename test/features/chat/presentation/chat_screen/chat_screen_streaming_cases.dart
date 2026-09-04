import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import '../../../../helpers/async/stream_markdown_test_animation.dart';
import 'chat_screen_test_helpers.dart';

void registerChatScreenStreamingTests() {
  testWidgets('聊天页流式展示回复并发送当前请求历史', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final controlled = fakeClient.enqueueControlledStream();

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await tester.enterText(find.byType(TextField), '帮我总结一下这个仓库的结构和当前能力');
    final sendButton = find.widgetWithText(FilledButton, '发送');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    // 受控流：等待 run 开始监听后逐步投递增量，不依赖真实延时。测试环境的
    // 内存库让 prepare 链路全为微任务，tap+pump 已驱动到监听，故 await 立即完成；
    // 内层 listened 无超时，外层 timeout 纯属冗余，挂死由 testWidgets 框架超时兜底。
    await controlled.listened;
    controlled.add(const ChatGenerationChunk(contentDelta: '第一段 '));
    await tester.pump();
    await pumpStreamMarkdownRefresh(tester);

    expect(find.textContaining('第一段'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '终止回答'), findsOneWidget);

    controlled.add(const ChatGenerationChunk(contentDelta: '第二段'));
    await controlled.close();
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '受控流关闭后生成完成',
    );

    expect(find.textContaining('帮我总结一下这个仓库'), findsWidgets);
    expect(find.textContaining('第一段 第二段'), findsWidgets);
    expect(
      fakeClient.lastRequestMessages.map((message) => message.role).toList(),
      [ChatMessageRole.user],
    );
    expect(fakeClient.lastRequestMessages.single.content, '帮我总结一下这个仓库的结构和当前能力');
    // 请求 target 命中活动模型的模型名（displayName 不在协议中立请求中）。
    expect(fakeClient.lastRequest?.target.model, equals('gpt-4.1'));
  });

  testWidgets('chat screen shows reasoning in a collapsible panel', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueDeltas([
        const ChatGenerationChunk(reasoningDelta: '这是思考过程'),
        const ChatGenerationChunk(contentDelta: '这是最终回复'),
      ]);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '请回答并返回思考过程');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '推理面板用例生成完成',
    );

    final reasoningExpand = find.semantics.byPredicate((node) {
      final data = node.getSemanticsData();
      return data.label == '深度思考' &&
          data.flagsCollection.isExpanded.toBoolOrNull() != null;
    });
    SemanticsData reasoningData() =>
        reasoningExpand.evaluate().single.getSemanticsData();
    expect(
      reasoningData().flagsCollection.isExpanded.toBoolOrNull(),
      isNotNull,
    );
    expect(reasoningData().flagsCollection.isExpanded.toBoolOrNull(), isFalse);
    expect(reasoningData().hint, '激活以展开');
    expect(find.text('这是思考过程'), findsNothing);
    expect(find.textContaining('这是最终回复'), findsWidgets);

    tester.semantics.tap(reasoningExpand);
    await settleAnimatedWidgetTransition(tester);

    expect(find.text('这是思考过程'), findsOneWidget);
    expect(reasoningData().flagsCollection.isExpanded.toBoolOrNull(), isTrue);
    expect(reasoningData().hint, '激活以收起');
  });

  testWidgets('chat screen copies raw message content without reasoning', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueDeltas([
        const ChatGenerationChunk(reasoningDelta: '这是思考过程'),
        const ChatGenerationChunk(contentDelta: '这是最终回复'),
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

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '请原样复制这条用户消息');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '复制用例生成完成',
    );

    expect(find.byTooltip('复制消息'), findsNWidgets(2));

    // 剪贴板写入是同步 mock 调用，复制动作本身无动画，单帧即可。
    await tester.tap(find.byTooltip('复制消息').first);
    await tester.pump();

    expect(
      (await Clipboard.getData('text/plain'))?.text,
      equals('请原样复制这条用户消息'),
    );

    await tester.tap(find.byTooltip('复制消息').last);
    await tester.pump();

    expect((await Clipboard.getData('text/plain'))?.text, equals('这是最终回复'));
    expect((await Clipboard.getData('text/plain'))?.text, isNot('这是思考过程'));
  });

  testWidgets('chat screen keeps user message markdown syntax as raw text', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['收到']);
    const userMessage = '**保留原样**\n- 这不是列表';

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, userMessage);
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: 'markdown 原样保留用例生成完成',
    );

    expect(find.text(userMessage), findsOneWidget);
    expect(find.textContaining('收到'), findsWidgets);
  });

  testWidgets('聊天页停止生成前显示确认对话框', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final streamController = StreamController<ChatGenerationChunk>();
    addTearDown(streamController.close);
    fakeClient.enqueueStream(streamController.stream);

    await pumpChatScreen(tester, fakeClient: fakeClient);

    await sendMessage(tester, '请开始长回复');
    await tester.pump();

    streamController.add(const ChatGenerationChunk(contentDelta: '已生成部分'));
    await tester.pump();
    await pumpStreamMarkdownRefresh(tester);

    await tester.tap(find.widgetWithText(FilledButton, '终止回答'));
    await tester.pump();
    expect(find.text('终止本次回答？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '继续生成'));
    await tester.pump();
    expect(find.text('终止本次回答？'), findsNothing);
    expect(find.widgetWithText(FilledButton, '终止回答'), findsOneWidget);
    expect(find.textContaining('已生成部分'), findsWidgets);
  });

  testWidgets('mobile layout renders composer and sends message', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['移动端回复']);

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(390, 844),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    // 移动端应使用紧凑布局的输入区
    expect(find.byType(TextField), findsOneWidget);

    await sendMessage(tester, '移动端测试消息');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '移动端用例生成完成',
    );

    expect(find.textContaining('移动端测试消息'), findsWidgets);
    expect(find.textContaining('移动端回复'), findsWidgets);
  });
}
