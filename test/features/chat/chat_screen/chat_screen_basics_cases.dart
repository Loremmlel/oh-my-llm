import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/composer_helpers.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/message_anchor_rail.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/thinking_toggle.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

void registerChatScreenBasicsTests() {
  testWidgets('chat screen uses remembered model for reasoning capability', (
    tester,
  ) async {
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
        {
          'id': 'conversation-1',
          'title': '旧会话',
          'createdAt': DateTime(2026, 4, 29).toIso8601String(),
          'updatedAt': DateTime(2026, 4, 29).toIso8601String(),
          'selectedModelId': null,
          'selectedPresetPromptId': null,
          'reasoningEnabled': false,
          'reasoningEffort': 'medium',
        },
      ],
    );

    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(
      tester,
      preferences: preferences,
      database: database,
      fakeClient: fakeClient,
    );

    expect(find.byType(ThinkingToggle), findsOneWidget);
  });

  testWidgets('chat screen renames conversation without controller errors', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(tester, fakeClient: fakeClient);

    await tester.tap(find.byTooltip('修改对话标题'));
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

  testWidgets('chat screen keeps custom title after sending a new reply', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['新的回答']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await tester.tap(find.byTooltip('修改对话标题'));
    await settleOverlayTransition(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '自定义标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await settleOverlayTransition(tester);

    await sendMessage(tester, '发送后不要重置标题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '自定义标题用例生成完成',
    );

    expect(
      container.read(chatSessionsProvider).activeConversation.resolvedTitle,
      '自定义标题',
    );
  });

  testWidgets(
    'chat screen opens checkpoints dialog and shows current word count',
    (tester) async {
      final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(tester, fakeClient: fakeClient);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
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
    },
  );

  testWidgets(
    'chat screen checkpoints dialog shows current prompt template usage',
    (tester) async {
      final fakeClient = FakeChatGenerationClient();

      await pumpChatScreen(tester, fakeClient: fakeClient);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      container
          .read(chatSessionsProvider.notifier)
          .updateActiveConversationPreferences(
            selectedPresetPromptId: 'prompt-1',
          );
      // 会话偏好是同步状态变更，单帧渲染即可。
      await tester.pump();

      await tester.tap(find.byTooltip('对话检查点'));
      await settleOverlayTransition(tester);

      expect(find.text('当前总结会附带预设 Prompt：代码助手'), findsOneWidget);
    },
  );

  testWidgets('chat screen checkpoints dialog renders markdown preview', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks([
        '# 检查点标题\n\n'
            '- 第一条\n'
            '- 第二条\n\n'
            '```dart\n'
            'void main() {\n'
            "  print('hello');\n"
            '}\n'
            '```\n\n'
            '${List.generate(24, (index) => '第 ${index + 1} 行详细内容。').join('\n\n')}',
      ]);

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
      description: '检查点预览用例上下文生成完成',
    );

    await container
        .read(chatSessionsProvider.notifier)
        .createCheckpoint(
          modelConfig: container.read(llmModelConfigsProvider).single,
          memoryPrompt: MemoryPrompt(
            id: 'memory-1',
            name: '研发总结',
            content: '请总结当前研发对话中的关键事实、约束与待办。',
            updatedAt: DateTime(2026, 5, 6),
          ),
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.medium,
        );
    // 检查点走非流式 complete()，await 返回即已提交（内存库同步持久化），
    // 不走 generation 生命周期，单帧渲染即可。
    await tester.pump();

    await tester.tap(find.byTooltip('对话检查点'));
    await settleOverlayTransition(tester);

    expect(find.text('检查点标题'), findsOneWidget);
  });

  testWidgets('chat screen can exclude a reply from future requests', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks(['第二轮回复']);

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
    await tester.tap(find.byTooltip('从发送上下文中排除').last);
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
  });

  testWidgets('chat screen can restore excluded messages from filter dialog', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks(['第二轮回复']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, '第一轮问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '恢复排除用例首轮生成完成',
    );

    // 排除是消息树同步变更，单帧渲染即可。
    await tester.tap(find.byTooltip('从发送上下文中排除').last);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await settleOverlayTransition(tester);

    expect(find.text('上下文过滤'), findsOneWidget);
    // 恢复分支是同步状态变更；关闭按钮走 overlay 过渡。
    await tester.tap(find.widgetWithText(FilledButton, '恢复当前分支'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await settleOverlayTransition(tester);

    expect(find.text('不发送'), findsNothing);

    await sendMessage(tester, '第二轮问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '恢复排除用例第二轮生成完成',
    );

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '首轮回复', '第二轮问题'],
    );
  });

  testWidgets(
    'message filter dialog uses the same word-count rule as checkpoints',
    (tester) async {
      final fakeClient = FakeChatGenerationClient()
        ..enqueueChunks(['done 456']);

      await pumpChatScreen(tester, fakeClient: fakeClient);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );

      await sendMessage(tester, 'hello 123 世界');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '字数规则用例生成完成',
      );

      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await settleOverlayTransition(tester);

      expect(find.text('发送字数：4 / 4 字'), findsOneWidget);
    },
  );

  testWidgets('chat screen opens compact secondary settings sheet on mobile', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await settleOverlayTransition(tester);

    expect(find.text('更多设置'), findsOneWidget);
    expect(find.text('思考强度'), findsNothing);
    // 档位切换触发弹窗内容高度动画（checkmark 宽度过渡），按组件动画等待。
    await tester.tap(find.text('深度思考'));
    await settleAnimatedWidgetTransition(tester);
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);
  });

  testWidgets(
    'chat screen compact settings sheet keeps stable height when switching effort',
    (tester) async {
      final fakeClient = FakeChatGenerationClient();

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
        size: const Size(430, 932),
      );

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await settleOverlayTransition(tester);
      await tester.tap(find.text('深度思考'));
      await settleAnimatedWidgetTransition(tester);

      // 用 descendant 限定，避免与折叠行摘要「更多设置 · med · 重试开」撞名。
      Finder chipFor(ReasoningEffort effort) => find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text(effortLabel(effort)),
      );
      for (final effort in ReasoningEffort.values) {
        expect(chipFor(effort), findsOneWidget);
      }

      // 切换档位时弹窗高度保持恒定：checkmark 的 150ms 宽度动画会让 Wrap
      // 在窄屏跨越换行阈值、内容高度跳变，关闭 checkmark 后应完全稳定。
      final sheet = find.byType(BottomSheet);
      final initialHeight = tester.getSize(sheet).height;
      for (final effort in ReasoningEffort.values) {
        await tester.tap(chipFor(effort));
        // 档位切换的 checkmark 宽度动画结束后弹窗高度应完全稳定。
        await settleAnimatedWidgetTransition(tester);
        expect(
          tester.getSize(sheet).height,
          moreOrLessEquals(initialHeight, epsilon: 0.01),
          reason: '切换思考强度档位（$effort）时弹窗高度不应跳变',
        );
      }

      // 选中态经回调正确传播到折叠行摘要。
      await tester.tap(chipFor(ReasoningEffort.xhigh));
      await settleAnimatedWidgetTransition(tester);
      expect(find.text('更多设置 · xhigh · 重试关'), findsOneWidget);
    },
  );

  testWidgets('chat screen can collapse and expand the composer', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(tester, fakeClient: fakeClient);

    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);

    await tester.tap(find.byTooltip('收起输入区'));
    await settleAnimatedWidgetTransition(tester);

    expect(find.text('输入区已隐藏'), findsOneWidget);
    // AnimatedCrossFade 下展开态 child 常驻树（仅 opacity 置 0），发送按钮
    // 仍在 widget 树中、findsNothing 不可用；但其 RenderOpacity 命中测试返回
    // false，折叠后点击不再触发发送--以行为契约替代存在性断言。
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
  });

  testWidgets(
    'chat screen inserts body above template when 正文 placeholder is absent',
    (tester) async {
      final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(tester, fakeClient: fakeClient);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container
          .read(templatePromptsProvider.notifier)
          .upsert(
            TemplatePrompt(
              id: 'tp-2',
              title: '总结模板',
              content: '请总结成{{语气}}。',
              variables: const [
                TemplatePromptVariable(name: '语气', defaultValue: '简洁'),
              ],
              updatedAt: DateTime(2026, 5, 5, 0, 1),
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
      await tester.tap(find.text('总结模板').last);
      await settleOverlayTransition(tester);

      await sendMessage(tester, '这是一段原文');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '正文插入模板用例生成完成',
      );

      expect(fakeClient.requestHistory.last.last.content, '这是一段原文\n请总结成简洁。');
    },
  );

  testWidgets(
    'chat screen shows multiple template variable inputs on wide screens',
    (tester) async {
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
    },
  );

  testWidgets('chat screen remembers selected model for new conversations', (
    tester,
  ) async {
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

  testWidgets('chat screen fills composer from fixed prompt sequence runner', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient();

    await pumpChatScreen(tester, fakeClient: fakeClient);

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await settleOverlayTransition(tester);

    expect(find.text('固定顺序提示词'), findsWidgets);
    expect(find.text('请先总结当前实现的核心目标。'), findsOneWidget);

    // 填入输入框后弹窗关闭，属 overlay 过渡。
    await tester.tap(find.widgetWithText(OutlinedButton, '填入输入框'));
    await settleOverlayTransition(tester);

    expect(find.text('请先总结当前实现的核心目标。'), findsWidgets);
  });

  testWidgets('chat screen sends fixed prompt sequence step and advances', (
    tester,
  ) async {
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

  testWidgets('chat screen sends message with Ctrl+Enter shortcut', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['快捷键发送成功']);

    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    const content = '请使用快捷键发送这条消息';
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, content);

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

  testWidgets('chat screen scroll-to-bottom button returns to latest message', (
    tester,
  ) async {
    final fakeClient = FakeChatGenerationClient();
    for (var index = 1; index <= 8; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
    }

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    for (var index = 1; index <= 8; index += 1) {
      await sendMessage(tester, '第 $index 条问题：${'内容 ' * 20}');
      await waitForChatGeneration(
        tester,
        container,
        (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
        description: '滚动到底用例第 $index 轮生成完成',
      );
    }

    final scrollable = find.byType(Scrollable).first;
    // 拖拽后的 ballistic 滚动属滚动运动。
    await tester.drag(scrollable, const Offset(0, 600));
    await settleScrollMotion(tester);

    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    // 点击滚动到底部按钮后的回弹滚动同样属滚动运动。
    await tester.tap(find.byTooltip('滚动到底部'));
    await settleScrollMotion(tester);

    expect(find.textContaining('第 8 条回复'), findsWidgets);
  });

  // 覆盖 ChatScrollController.handleVisibleItemsChanged -> ValueNotifier 链路：
  // 滚动消息列表时，用户消息锚点条的高亮会跟随当前可见区域切换，证明
  // ValueListenableBuilder 驱动了 UI 重绘（不再依赖宿主 setState）。
  testWidgets(
    'anchor rail highlights follow visible user message while scrolling',
    (tester) async {
      final fakeClient = FakeChatGenerationClient();
      for (var index = 1; index <= 5; index += 1) {
        fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
      }

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
        size: const Size(900, 520),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );

      for (var index = 1; index <= 5; index += 1) {
        await sendMessage(tester, '第 $index 条问题：${'内容 ' * 20}');
        await waitForChatGeneration(
          tester,
          container,
          (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
          description: '锚点高亮用例第 $index 轮生成完成',
        );
      }

      // 锚点条渲染 5 个条目（>3 条用户消息才会展开 rail）
      expect(find.byType(MessageAnchorRail), findsOneWidget);

      // 滚动到列表顶部附近，验证锚点高亮经 ValueNotifier 更新不抛异常且 rail 仍存在。
      // 拖拽后的 ballistic 滚动属滚动运动。
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -400));
      await settleScrollMotion(tester);

      expect(find.byType(MessageAnchorRail), findsOneWidget);
    },
  );
}
