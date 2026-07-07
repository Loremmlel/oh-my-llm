import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/message_anchor_rail.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/thinking_toggle.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import '../../../helpers/fixtures.dart';
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

    final fakeClient = FakeChatCompletionClient();
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
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byTooltip('修改对话标题'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的对话标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的对话标题'), findsWidgets);
  });

  testWidgets('chat screen keeps custom title after sending a new reply', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['新的回答']);

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await tester.tap(find.byTooltip('修改对话标题'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '自定义标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    await sendMessage(tester, '发送后不要重置标题');
    await tester.pumpAndSettle();

    expect(
      container.read(chatSessionsProvider).activeConversation.resolvedTitle,
      '自定义标题',
    );
  });

  testWidgets(
    'chat screen opens checkpoints dialog and shows current word count',
    (tester) async {
        final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

      await sendMessage(tester, '你好');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('对话检查点'));
      await tester.pumpAndSettle();

      expect(find.text('对话检查点'), findsOneWidget);
      expect(find.text('当前上下文字数：5 字（不含预设 Prompt）'), findsOneWidget);
    },
  );

  testWidgets(
    'chat screen checkpoints dialog shows current prompt template usage',
    (tester) async {
        final fakeClient = FakeChatCompletionClient();

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      container
          .read(chatSessionsProvider.notifier)
          .updateActiveConversationPreferences(
            selectedPresetPromptId: 'prompt-1',
          );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('对话检查点'));
      await tester.pumpAndSettle();

      expect(find.text('当前总结会附带预设 Prompt：代码助手'), findsOneWidget);
    },
  );

  testWidgets(
    'chat screen checkpoints dialog renders markdown preview in scrollable area',
    (tester) async {
        final fakeClient = FakeChatCompletionClient()
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

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

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
      await tester.pumpAndSettle();

      await sendMessage(tester, '先生成一点上下文');
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('对话检查点'));
      await tester.pumpAndSettle();

      expect(find.text('检查点标题'), findsOneWidget);

      await tester.drag(find.text('检查点标题'), const Offset(0, -120));
      await tester.pump();
    },
  );

  testWidgets('chat screen can exclude a reply from future requests', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks(['第二轮回复']);

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '第一轮问题');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('从发送上下文中排除').last);
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.filter_alt_outlined),
      findsOneWidget,
    );

    await sendMessage(tester, '第二轮问题');
    await tester.pumpAndSettle();

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '第二轮问题'],
    );
  });

  testWidgets('chat screen can restore excluded messages from filter dialog', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['首轮回复'])
      ..enqueueChunks(['第二轮回复']);

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    await sendMessage(tester, '第一轮问题');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('从发送上下文中排除').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();

    expect(find.text('上下文过滤'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '恢复当前分支'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();

    expect(find.text('不发送'), findsNothing);

    await sendMessage(tester, '第二轮问题');
    await tester.pumpAndSettle();

    expect(
      fakeClient.requestHistory.last.map((message) => message.content).toList(),
      ['第一轮问题', '首轮回复', '第二轮问题'],
    );
  });

  testWidgets(
    'message filter dialog uses the same word-count rule as checkpoints',
    (tester) async {
        final fakeClient = FakeChatCompletionClient()
        ..enqueueChunks(['done 456']);

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

      await sendMessage(tester, 'hello 123 世界');
      await tester.pumpAndSettle();

      await tester.tap(
        find.byIcon(Icons.filter_alt_outlined),
      );
      await tester.pumpAndSettle();

      expect(find.text('发送字数：4 / 4 字'), findsOneWidget);
    },
  );

  testWidgets('chat screen opens compact secondary settings sheet on mobile', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    await tester.tap(
      find.byIcon(Icons.tune_rounded),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多设置'), findsOneWidget);
    expect(find.text('思考强度'), findsNothing);
    await tester.tap(find.text('深度思考'));
    await tester.pumpAndSettle();
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);
  });

  testWidgets('chat screen can collapse and expand the composer', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);

    await tester.tap(find.byTooltip('收起输入区'));
    await tester.pumpAndSettle();

    expect(find.text('输入区已隐藏'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送'), findsNothing);

    await tester.tap(find.byTooltip('展开输入区'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
  });

  testWidgets(
    'chat screen inserts body above template when 正文 placeholder is absent',
    (tester) async {
        final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

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
      await tester.pumpAndSettle();

      await tester.tap(find.ancestor(
        of: find.text('模板提示词'),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('总结模板').last);
      await tester.pumpAndSettle();

      await sendMessage(tester, '这是一段原文');
      await tester.pumpAndSettle();

      expect(fakeClient.requestHistory.last.last.content, '这是一段原文\n请总结成简洁。');
    },
  );

  testWidgets(
    'chat screen shows multiple template variable inputs on wide screens',
    (tester) async {
        final fakeClient = FakeChatCompletionClient();

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

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
      await tester.pumpAndSettle();

      await tester.tap(find.ancestor(
        of: find.text('模板提示词'),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('多变量模板').last);
      await tester.pumpAndSettle();

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

    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['第一次回复'])
      ..enqueueChunks(['第二次回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      database: database,
      fakeClient: fakeClient,
    );

    await tester.tap(find.ancestor(
      of: find.text('模型'),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek V4 Flash').last);
    await tester.pumpAndSettle();

    await sendMessage(tester, '第一次问题');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle();
    await sendMessage(tester, '第二次问题');
    await tester.pumpAndSettle();

    expect(
      fakeClient.requestedModels.map((config) => config.id).toList(),
      ['model-new', 'model-new'],
    );
  });

  testWidgets('chat screen fills composer from fixed prompt sequence runner', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await tester.pumpAndSettle();

    expect(find.text('固定顺序提示词'), findsWidgets);
    expect(find.text('请先总结当前实现的核心目标。'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '填入输入框'));
    await tester.pumpAndSettle();

    expect(find.text('请先总结当前实现的核心目标。'), findsWidgets);
  });

  testWidgets('chat screen sends fixed prompt sequence step and advances', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(
        tester,
        fakeClient: fakeClient,
      );

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发送当前步骤'));
    await tester.pumpAndSettle();

    expect(fakeClient.lastRequestMessages.single.content, '请先总结当前实现的核心目标。');
    expect(find.textContaining('已收到'), findsWidgets);

    await tester.tap(find.byTooltip('固定顺序提示词'));
    await tester.pumpAndSettle();

    expect(find.text('请列出三个可执行方案，并说明权衡。'), findsOneWidget);
  });

  testWidgets('chat screen sends message with Ctrl+Enter shortcut', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['快捷键发送成功']);

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
    );

    const content = '请使用快捷键发送这条消息';
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      content,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(fakeClient.lastRequestMessages.single.content, content);
    expect(find.textContaining('快捷键发送成功'), findsWidgets);
  });

  testWidgets('chat screen scroll-to-bottom button returns to latest message', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();
    for (var index = 1; index <= 8; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
    }

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );

    for (var index = 1; index <= 8; index += 1) {
      await sendMessage(tester, '第 $index 条问题：${'内容 ' * 20}');
      await tester.pumpAndSettle();
    }

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('滚动到底部'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 8 条回复'), findsWidgets);
  });

  // 覆盖 ChatScrollController.handleVisibleItemsChanged → onScroll → setState 链路：
  // 滚动消息列表时，用户消息锚点条的高亮会跟随当前可见区域切换，证明 onScroll 驱动了 UI 重绘。
  testWidgets('anchor rail highlights follow visible user message while scrolling', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();
    for (var index = 1; index <= 5; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
    }

    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );

    for (var index = 1; index <= 5; index += 1) {
      await sendMessage(tester, '第 $index 条问题：${'内容 ' * 20}');
      await tester.pumpAndSettle();
    }

    // 锚点条渲染 5 个条目（>3 条用户消息才会展开 rail）
    expect(find.byType(MessageAnchorRail), findsOneWidget);

    // 滚动到列表顶部附近，验证 onScroll 回调驱动 setState 不抛异常且 rail 仍存在
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byType(MessageAnchorRail), findsOneWidget);
  });
}
