import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/application/prompts/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../../../helpers/async/async_test_signals.dart';
import '../../../../helpers/async/stream_markdown_test_animation.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

Map<String, dynamic> _conversationWithTurns(int turnCount) {
  final nodes = <ChatMessage>[];
  final selections = <String, String>{};
  var parentId = rootConversationParentId;
  final createdAt = DateTime(2026, 5, 5, 10);
  for (var index = 1; index <= turnCount; index++) {
    final userId = 'user-$index';
    final assistantId = 'assistant-$index';
    nodes.add(
      ChatMessage(
        id: userId,
        role: ChatMessageRole.user,
        content: '第 $index 条问题：${'内容 ' * 20}',
        parentId: parentId,
        createdAt: createdAt.add(Duration(minutes: index * 2)),
      ),
    );
    nodes.add(
      ChatMessage(
        id: assistantId,
        role: ChatMessageRole.assistant,
        content: '第 $index 条回复：${'内容 ' * 20}',
        parentId: userId,
        createdAt: createdAt.add(Duration(minutes: index * 2 + 1)),
      ),
    );
    selections[parentId] = userId;
    selections[userId] = assistantId;
    parentId = assistantId;
  }

  return ChatConversation(
    id: 'conversation-with-$turnCount-turns',
    title: '长会话',
    messageNodes: nodes,
    selectedChildByParentId: selections,
    createdAt: createdAt,
    updatedAt: createdAt.add(Duration(minutes: turnCount * 2 + 1)),
  ).toJson();
}

void registerChatScreenBasicsTests() {
  testWidgets('通过更多菜单修改对话标题并保存', (tester) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(tester, fakeClient: fakeClient);

    await tester.tap(find.byTooltip('更多对话操作'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('修改对话标题'));
    await settleOverlayTransition(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的对话标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settleOverlayTransition(tester);

    expect(find.text('新的对话标题'), findsWidgets);
  });

  testWidgets('检查点窗口显示当前字数和选中预设，字数不含预设', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: 'prompt-1',
        );

    await sendMessage(tester, '你好');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '检查点字数用例生成完成',
    );

    await tester.tap(find.byTooltip('对话检查点'));
    await settleOverlayTransition(tester);

    expect(find.text('对话检查点'), findsOneWidget);
    expect(find.text('当前上下文字数：5 字（不含预设 Prompt）'), findsOneWidget);
    expect(find.text('当前总结会附带预设 Prompt：代码助手'), findsOneWidget);
  });

  testWidgets('创建检查点期间 system Back 不能关闭对话框，完成后可关闭', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    // 创建检查点走非流式 complete()，受控流不结束即保持 _isCreating=true。
    final controlled = fakeClient.enqueueControlledStream();

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(memoryPromptsProvider.notifier)
        .upsert(
          MemoryPrompt(
            id: 'memory-1',
            name: '研发总结',
            content: '请总结当前研发对话中的关键事实、约束与待办。',
            updatedAt: DateTime(2026, 5, 6),
          ),
        );
    // upsert 是同步持久化，单帧渲染即可。
    await tester.pump();

    await sendMessage(tester, '先生成一点上下文');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '检查点 busy 用例上下文生成完成',
    );

    await tester.tap(find.byTooltip('对话检查点'));
    await settleOverlayTransition(tester);

    await tester.tap(find.widgetWithText(FilledButton, '创建检查点'));
    // 确认 complete() 已开始监听受控流，再进入 busy 断言。
    await controlled.listened;
    await tester.pump();

    expect(find.text('总结中...'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pump();
    expect(find.text('对话检查点'), findsOneWidget);

    // busy 期间 system Back 不能关闭对话框（PopScope canPop=false）。
    await tester.binding.handlePopRoute();
    // 等退场动画收敛：若路由真的在退场，动画结束后对话框必然消失，
    // 单帧 pump 只会停在退场中途、树里仍有对话框，无法区分二者。
    await settleOverlayTransition(tester);
    expect(find.text('对话检查点'), findsOneWidget);

    // 检查点创建完成（busy 恢复 false）后，Back 可以关闭。
    controlled.add(const ChatGenerationChunk(contentDelta: '检查点内容'));
    await controlled.close();
    await waitForProviderState(
      container: container,
      provider: chatSessionsProvider,
      matches: (s) => !s.isCheckpointing,
      description: '检查点创建完成',
    );
    await tester.pump();

    expect(find.text('总结中...'), findsNothing);

    await tester.binding.handlePopRoute();
    await settleOverlayTransition(tester);
    expect(find.text('对话检查点'), findsNothing);
  });

  testWidgets('排除回复改变下轮请求，过滤窗口恢复后再次发送包含原回复', (tester) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks(['第二轮回复'])
      ..enqueueChunks(['第三轮回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '第一轮问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '排除回复用例首轮生成完成',
    );

    // 排除是消息树同步变更，单帧渲染即可。
    await tester.tap(find.byTooltip('消息操作').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('从发送上下文中排除'));
    await settleOverlayTransition(tester);
    await tester.pump();

    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);

    await sendMessage(tester, '第二轮问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '排除回复用例第二轮生成完成',
    );

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '第二轮问题'],
    );
    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await settleOverlayTransition(tester);

    expect(find.text('上下文过滤'), findsOneWidget);
    // 恢复分支是同步状态变更；关闭按钮走 overlay 过渡。
    await tester.tap(find.widgetWithText(FilledButton, '恢复当前分支'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await settleOverlayTransition(tester);

    expect(find.text('不发送'), findsNothing);

    await sendMessage(tester, '第三轮问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '恢复后第三轮生成完成',
    );

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '首轮回复', '第二轮问题', '第二轮回复', '第三轮问题'],
    );
  });

  testWidgets('窄屏更多设置显示命中率并将思考强度同步到摘要', (tester) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settleOverlayTransition(tester);
    expect(find.text('当前会话缓存命中率：暂无数据'), findsOneWidget);
    expect(find.text('思考强度'), findsNothing);
    await tester.tap(find.text('深度思考'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);

    await tester.tap(find.text('xhigh'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.byTooltip('更多设置 · xhigh · 重试关'), findsOneWidget);
  });

  testWidgets('收起输入区不能发送有效草稿，展开后保留草稿并可发送', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await tester.enterText(chatMessageComposerFinder, '等待展开后发送');
    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);

    await tester.tap(find.byTooltip('收起输入区'));
    await settleAnimatedWidgetTransition(tester);

    expect(find.text('输入区已隐藏'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送').hitTestable(), findsNothing);
    await tester.tap(
      find.widgetWithText(FilledButton, '发送'),
      warnIfMissed: false,
    );
    // 折叠态下点击不产生任何请求，单帧处理该 tap 即可。
    await tester.pump();
    expect(fakeClient.requestHistory, isEmpty);

    await tester.tap(find.byTooltip('展开输入区'));
    await settleAnimatedWidgetTransition(tester);

    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
    expect(find.text('等待展开后发送'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase == ChatGenerationPhase.succeeded,
      description: '展开后发送草稿完成',
    );
    expect(fakeClient.lastRequestMessages.single.content, '等待展开后发送');
  });

  testWidgets('宽屏选择模板后显示全部变量输入', (tester) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(tester, fakeClient: fakeClient);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-grid',
            title: '多变量模板',
            content: '请按{{语气}}、{{长度}}、{{受众}}输出。',
            variables: const [
              TemplatePromptVariable(name: '语气', defaultValue: '正式'),
              TemplatePromptVariable(name: '长度', defaultValue: '简短'),
              TemplatePromptVariable(name: '受众', defaultValue: '开发者'),
            ],
            updatedAt: DateTime(2026, 5, 5, 0, 3),
          ),
        );
    // upsert 是同步持久化，单帧渲染即可。
    await tester.pump();

    // 下拉菜单开合属 overlay 过渡。
    await tester.tap(
      find.ancestor(
        of: find.text('模板提示词'),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      ),
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('多变量模板').last);
    await settleOverlayTransition(tester);

    expect(find.text('语气'), findsOneWidget);
    expect(find.text('长度'), findsOneWidget);
    expect(find.text('受众'), findsOneWidget);
  });

  testWidgets('无模型的旧会话使用默认能力，手动选择模型后新会话沿用该模型', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [
        TestFixtures.model(
          id: 'model-legacy',
          displayName: 'Legacy',
          modelName: 'legacy',
          supportsReasoning: false,
        ),
        TestFixtures.deepSeekV4().copyWith(id: 'model-new'),
      ],
      chatDefaults: {'defaultModelId': 'model-new'},
      conversations: [
        ChatConversation(
          id: 'legacy-conversation',
          title: '旧会话',
          createdAt: DateTime(2026, 4, 29),
          updatedAt: DateTime(2026, 4, 29),
        ).toJson(),
      ],
    );

    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['第一次回复'])
      ..enqueueChunks(['第二次回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      database: database,
      fakeClient: fakeClient,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    void expectThinkingEnabled(bool enabled) {
      expect(
        find.semantics
            .byLabel('深度思考')
            .evaluate()
            .single
            .getSemanticsData()
            .flagsCollection
            .isEnabled
            .toBoolOrNull(),
        enabled,
      );
    }

    expectThinkingEnabled(true);
    await tester.tap(
      find.ancestor(
        of: find.text('模型'),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      ),
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('Legacy').last);
    await settleOverlayTransition(tester);
    expectThinkingEnabled(false);

    // 模型下拉菜单开合属 overlay 过渡。
    await tester.tap(
      find.ancestor(
        of: find.text('模型'),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      ),
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('DeepSeek V4 Flash').last);
    await settleOverlayTransition(tester);
    expectThinkingEnabled(true);

    await sendMessage(tester, '第一次问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '模型记忆用例首轮生成完成',
    );
    // 新建对话是同步状态变更，单帧渲染即可。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pump();
    expectThinkingEnabled(true);
    await sendMessage(tester, '第二次问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '模型记忆用例第二轮生成完成',
    );

    // 两次请求都命中记忆中的模型（target.model = 模型名）。
    expect(fakeClient.requestedTargets.map((target) => target.model).toList(), [
      'deepseek-v4-flash',
      'deepseek-v4-flash',
    ]);
  });

  testWidgets('固定顺序提示词发送当前步骤后推进下一步', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '发送当前步骤'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '固定顺序发送生成完成',
    );

    expect(fakeClient.lastRequestMessages.single.content, '请先总结当前实现的核心目标。');
    expect(find.textContaining('已收到'), findsWidgets);

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await settleOverlayTransition(tester);

    expect(find.text('请列出三个可执行方案，并说明权衡。'), findsOneWidget);
  });

  testWidgets('Ctrl+Enter 发送当前正文并显示回复', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['快捷键发送成功']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    const content = '请使用快捷键发送这条消息';
    await tester.tap(chatMessageComposerFinder);
    await tester.pump();
    await tester.enterText(chatMessageComposerFinder, content);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '快捷键发送生成完成',
    );

    expect(fakeClient.lastRequestMessages.single.content, content);
    expect(find.textContaining('快捷键发送成功'), findsWidgets);
  });

  testWidgets('空会话首次发送后定位到新增助手消息', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final controlled = fakeClient.enqueueControlledStream();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '首轮问题${'很长的内容 ' * 200}');
    await controlled.listened;
    await tester.pump();
    await tester.pump();

    controlled.add(const ChatGenerationChunk(contentDelta: '首轮回复'));
    await tester.pump();
    await pumpStreamMarkdownRefresh(tester);
    expect(find.textContaining('首轮回复').hitTestable(), findsWidgets);
    await controlled.close();
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase == ChatGenerationPhase.succeeded,
      description: '空会话首轮滚动用例生成完成',
    );
  });

  testWidgets('长会话离开底部可返回最新消息，发送长问题后新增回复可见', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final controlled = fakeClient.enqueueControlledStream();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.gpt41()],
      conversations: [_conversationWithTurns(8)],
    );
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      preferences: preferences,
      database: database,
      size: const Size(900, 520),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await tester.pump();
    await tester.pump();

    // 先离开底部再返回，不依赖初次布局的换行高度恰好露出导航按钮。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await settleScrollMotion(tester);
    expect(find.byTooltip('滚动到底部'), findsOneWidget);
    await tester.tap(find.byTooltip('滚动到底部'));
    await settleScrollMotion(tester);
    expect(find.textContaining('第 8 条回复').hitTestable(), findsWidgets);

    await sendMessage(tester, '第九轮问题${'很长的内容 ' * 200}');
    await controlled.listened;
    await tester.pump();
    await tester.pump();

    controlled.add(const ChatGenerationChunk(contentDelta: '第九轮回复'));
    await tester.pump();
    await pumpStreamMarkdownRefresh(tester);
    expect(find.textContaining('第九轮回复').hitTestable(), findsWidgets);
    await controlled.close();
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase == ChatGenerationPhase.succeeded,
      description: '长会话新一轮滚动用例生成完成',
    );
  });

  // 覆盖 ChatScrollController.handleVisibleItemsChanged -> ValueNotifier 链路：
  // 滚动消息列表时，用户消息锚点条的高亮会跟随当前可见区域切换，证明
  // ValueListenableBuilder 驱动了 UI 重绘（不再依赖宿主 setState）。
  testWidgets('滚动时锚点条高亮跟随当前可见用户消息', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.gpt41()],
      conversations: [_conversationWithTurns(5)],
    );

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      preferences: preferences,
      database: database,
      size: const Size(900, 520),
    );

    int selectedAnchorIndex() {
      final selected = <int>[];
      for (var index = 1; index <= 5; index++) {
        final semantics = find.semantics
            .byLabel('第 $index 条用户消息：第 $index 条问题')
            .evaluate()
            .single;
        if (semantics
                .getSemanticsData()
                .flagsCollection
                .isSelected
                .toBoolOrNull() ==
            true) {
          selected.add(index);
        }
      }
      expect(selected, hasLength(1));
      return selected.single;
    }

    final beforeScroll = selectedAnchorIndex();

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 400));
    await settleScrollMotion(tester);

    expect(selectedAnchorIndex(), isNot(beforeScroll));
    expect(tester.takeException(), isNull);
  });
}
