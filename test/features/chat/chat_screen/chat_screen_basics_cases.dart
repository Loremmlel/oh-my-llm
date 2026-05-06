import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/thinking_toggle.dart';
import 'package:oh_my_llm/features/settings/application/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenBasicsTests() {
  testWidgets('chat screen shows core workspace controls', (tester) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    expect(find.byKey(const ValueKey('chat-model-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-prompt-selector')), findsOneWidget);
    expect(find.text('消息定位条'), findsNothing);
    expect(find.byKey(const ValueKey('message-anchor-rail')), findsNothing);
    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.text('未命名对话'), findsOneWidget);
    expect(find.textContaining('深度思考：'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(SegmentedButton<ReasoningEffort>), findsNothing);
    // ThinkingToggle 现在是纯 pill，不含 Switch
    expect(find.byType(Switch), findsNothing);
    // 默认未开启深度思考时，不再常驻显示思考强度控件。
    expect(find.byTooltip('思考强度'), findsNothing);
  });

  testWidgets('chat screen uses remembered model for reasoning capability', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-legacy',
          'displayName': 'Legacy',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'legacy',
          'supportsReasoning': false,
        },
        {
          'id': 'model-new',
          'displayName': 'DeepSeek V4 Flash',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'deepseek-v4-flash',
          'supportsReasoning': true,
        },
      ]),
      chatDefaultsStorageKey: jsonEncode({'defaultModelId': 'model-new'}),
      chatConversationsStorageKey: jsonEncode([
        {
          'id': 'conversation-1',
          'title': '旧会话',
          'messages': [],
          'createdAt': DateTime(2026, 4, 29).toIso8601String(),
          'updatedAt': DateTime(2026, 4, 29).toIso8601String(),
          'selectedModelId': null,
          'selectedPromptTemplateId': null,
          'reasoningEnabled': false,
          'reasoningEffort': 'medium',
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    final toggle = tester.widget<ThinkingToggle>(find.byType(ThinkingToggle));
    expect(toggle.enabled, isTrue);
  });

  testWidgets('chat screen can send template prompt with empty 正文', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-empty-body',
            title: '模板直发',
            content: '请输出{{风格}}版摘要。',
            variables: const [
              TemplatePromptVariable(name: '风格', defaultValue: '简洁'),
            ],
            updatedAt: DateTime(2026, 5, 5, 0, 2),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('template-prompt-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模板直发').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();

    expect(fakeClient.requestHistory.last.last.content, '请输出简洁版摘要。');
  });

  testWidgets('chat screen keeps spacing between template selector and 正文', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    final selectorRect = tester.getRect(
      find.byKey(const ValueKey('template-prompt-selector')),
    );
    final composerRect = tester.getRect(
      find.byKey(const ValueKey('chat-message-composer')),
    );

    expect(composerRect.top, greaterThanOrEqualTo(selectorRect.bottom + 12));
  });

  testWidgets('chat screen custom title item hides preview in history panel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-1',
          'displayName': 'DeepSeek V4 Flash',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'deepseek-v4-flash',
          'supportsReasoning': true,
        },
      ]),
      chatConversationsStorageKey: jsonEncode([
        {
          'id': 'conversation-1',
          'title': '这是一段超长的用户自定义历史标题用于验证两行显示',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'content': '这段文本只用于生成预览',
              'createdAt': DateTime(2026, 4, 29).toIso8601String(),
            },
          ],
          'createdAt': DateTime(2026, 4, 29).toIso8601String(),
          'updatedAt': DateTime(2026, 4, 29).toIso8601String(),
          'selectedModelId': 'model-1',
          'selectedPromptTemplateId': null,
          'reasoningEnabled': false,
          'reasoningEffort': 'medium',
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    final historyTile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(historyTile.subtitle, isNull);
    final titleText = historyTile.title! as Tooltip;
    final titleWidget = titleText.child! as Text;
    expect(titleWidget.maxLines, 2);
  });

  testWidgets('chat screen renames conversation without controller errors', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
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

    expect(find.text('新的对话标题'), findsOneWidget);
  });

  testWidgets('chat screen keeps composer visible on compact layouts', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    expect(find.byType(ListView), findsNothing);
    expect(
      find.widgetWithText(FilledButton, '发送').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-secondary-settings-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-prompt-selector')), findsNothing);
  });

  testWidgets('chat screen opens compact secondary settings sheet on mobile', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    await tester.tap(find.byKey(const ValueKey('chat-secondary-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('更多设置'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-prompt-selector')), findsOneWidget);
    expect(find.text('思考强度'), findsNothing);
    await tester.tap(find.text('深度思考'));
    await tester.pumpAndSettle();
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);
  });

  testWidgets('chat screen can collapse and expand the composer', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
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

  testWidgets('chat screen applies selected template prompt to user message', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-1',
            title: '翻译模板',
            content: '请把{{正文}}翻译成{{目标语言}}。',
            variables: const [
              TemplatePromptVariable(name: templatePromptBodyVariableName),
              TemplatePromptVariable(name: '目标语言', defaultValue: '英文'),
            ],
            updatedAt: DateTime(2026, 5, 5),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('template-prompt-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译模板').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('template-variable-目标语言')),
      '法文',
    );
    await sendMessage(tester, '你好');
    await tester.pumpAndSettle();

    expect(fakeClient.requestHistory.last.last.content, '请把你好翻译成法文。');

    final userMessage = container
        .read(activeChatConversationProvider)
        .messages
        .firstWhere((message) => message.role == ChatMessageRole.user);
    expect(userMessage.userMessageSegments, const [
      UserMessageSegment(text: '请把', kind: UserMessageSegmentKind.template),
      UserMessageSegment(text: '你好', kind: UserMessageSegmentKind.body),
      UserMessageSegment(text: '翻译成法文。', kind: UserMessageSegmentKind.template),
    ]);

    final richTextFinder = find.byWidgetPredicate((widget) {
      return widget is SelectableText &&
          widget.textSpan?.toPlainText() == '请把你好翻译成法文。';
    });
    final rendered = tester.widget<SelectableText>(richTextFinder.first);
    final spans = rendered.textSpan!.children!.cast<TextSpan>();
    final theme = Theme.of(tester.element(richTextFinder.first));
    expect(
      spans[0].style?.color,
      theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.62),
    );
    expect(spans[1].style?.color, theme.colorScheme.onPrimaryContainer);
    expect(
      spans[2].style?.color,
      theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.62),
    );
  });

  testWidgets(
    'chat screen inserts body above template when 正文 placeholder is absent',
    (tester) async {
      final preferences = await createSeededPreferences();
      final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

      await pumpChatScreen(
        tester,
        preferences: preferences,
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

      await tester.tap(find.byKey(const ValueKey('template-prompt-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('总结模板').last);
      await tester.pumpAndSettle();

      await sendMessage(tester, '这是一段原文');
      await tester.pumpAndSettle();

      expect(fakeClient.requestHistory.last.last.content, '这是一段原文\n请总结成简洁。');
    },
  );

  testWidgets(
    'chat screen lays out template variables compactly on wide screens',
    (tester) async {
      final preferences = await createSeededPreferences();
      final fakeClient = FakeChatCompletionClient();

      await pumpChatScreen(
        tester,
        preferences: preferences,
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

      await tester.tap(find.byKey(const ValueKey('template-prompt-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('多变量模板').last);
      await tester.pumpAndSettle();

      final toneRect = tester.getRect(
        find.byKey(const ValueKey('template-variable-语气')),
      );
      final lengthRect = tester.getRect(
        find.byKey(const ValueKey('template-variable-长度')),
      );

      expect(toneRect.top, lengthRect.top);
      expect(lengthRect.left, greaterThan(toneRect.left));
    },
  );

  testWidgets('chat screen remembers selected model for new conversations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-legacy',
          'displayName': 'Legacy',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'legacy',
          'supportsReasoning': false,
        },
        {
          'id': 'model-new',
          'displayName': 'DeepSeek V4 Flash',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test',
          'modelName': 'deepseek-v4-flash',
          'supportsReasoning': true,
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['第一次回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byKey(const ValueKey('chat-model-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek V4 Flash').last);
    await tester.pumpAndSettle();

    await sendMessage(tester, '第一次问题');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(container.read(chatDefaultsProvider).defaultModelId, 'model-new');
    expect(
      container.read(activeChatConversationProvider).selectedModelId,
      'model-new',
    );
  });

  testWidgets('chat screen fills composer from fixed prompt sequence runner', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
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
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
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
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['快捷键发送成功']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    const content = '请使用快捷键发送这条消息';
    await tester.tap(find.byKey(const ValueKey('chat-message-composer')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-composer')),
      content,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(fakeClient.lastRequestMessages.single.content, content);
    expect(find.textContaining('快捷键发送成功'), findsWidgets);
  });

  testWidgets('chat screen anchor rail does not render a scrollbar', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    for (var index = 1; index <= 12; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复']);
    }

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );

    for (var index = 1; index <= 12; index += 1) {
      await sendMessage(tester, '第 $index 条问题');
      await tester.pumpAndSettle();
    }

    final rail = find.byKey(const ValueKey('message-anchor-rail'));
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.byType(Scrollbar)),
      findsNothing,
    );
  });

  testWidgets('chat screen scroll-to-bottom button returns to latest message', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    for (var index = 1; index <= 8; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
    }

    await pumpChatScreen(
      tester,
      preferences: preferences,
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

  testWidgets('chat screen remembers selected Prompt for new conversations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-1',
          'displayName': 'GPT-4.1',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test-12345678',
          'modelName': 'gpt-4.1',
          'supportsReasoning': true,
        },
      ]),
      promptTemplatesStorageKey: jsonEncode([
        {
          'id': 'prompt-1',
          'name': '模板一',
          'systemPrompt': '',
          'messages': [
            {
              'id': 'prompt-1-message-1',
              'role': 'user',
              'content': '模板一前置',
              'placement': 'before',
            },
          ],
          'updatedAt': DateTime(2026, 4, 30).toIso8601String(),
        },
        {
          'id': 'prompt-2',
          'name': '模板二',
          'systemPrompt': '',
          'messages': [
            {
              'id': 'prompt-2-message-1',
              'role': 'user',
              'content': '模板二前置',
              'placement': 'before',
            },
          ],
          'updatedAt': DateTime(2026, 4, 30, 0, 1).toIso8601String(),
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['第一次回复'])
      ..enqueueChunks(['第二次回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byKey(const ValueKey('chat-prompt-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模板二').last);
    await tester.pumpAndSettle();

    await sendMessage(tester, '第一次问题');
    await tester.pumpAndSettle();
    expect(fakeClient.requestHistory.first.first.content, '模板二前置');

    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle();
    await sendMessage(tester, '第二次问题');
    await tester.pumpAndSettle();

    final requestContents = fakeClient.requestHistory.last
        .map((message) => message.content)
        .toList(growable: false);
    expect(requestContents.first, '模板二前置');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatDefaultsProvider).defaultPromptTemplateId,
      'prompt-2',
    );
  });

  testWidgets('chat screen can clear remembered Prompt from selector', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      llmModelConfigsStorageKey: jsonEncode([
        {
          'id': 'model-1',
          'displayName': 'GPT-4.1',
          'apiUrl': 'https://api.example.com/v1/chat/completions',
          'apiKey': 'sk-test-12345678',
          'modelName': 'gpt-4.1',
          'supportsReasoning': true,
        },
      ]),
      promptTemplatesStorageKey: jsonEncode([
        {
          'id': 'prompt-1',
          'name': '模板一',
          'systemPrompt': '',
          'messages': [
            {
              'id': 'prompt-1-message-1',
              'role': 'user',
              'content': '模板一前置',
              'placement': 'before',
            },
          ],
          'updatedAt': DateTime(2026, 4, 30).toIso8601String(),
        },
      ]),
      chatDefaultsStorageKey: jsonEncode({
        'defaultPromptTemplateId': 'prompt-1',
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['第一次回复'])
      ..enqueueChunks(['第二次回复']);

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byKey(const ValueKey('chat-prompt-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不使用前置 Prompt').last);
    await tester.pumpAndSettle();

    await sendMessage(tester, '第一次问题');
    await tester.pumpAndSettle();

    final firstRequestContents = fakeClient.requestHistory.first
        .map((message) => message.content)
        .toList(growable: false);
    expect(firstRequestContents, ['第一次问题']);

    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle();
    await sendMessage(tester, '第二次问题');
    await tester.pumpAndSettle();

    final lastRequestContents = fakeClient.requestHistory.last
        .map((message) => message.content)
        .toList(growable: false);
    expect(lastRequestContents, ['第二次问题']);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatDefaultsProvider).defaultPromptTemplateId,
      isNull,
    );
  });
}
