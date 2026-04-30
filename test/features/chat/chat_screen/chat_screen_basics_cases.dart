import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/chat/data/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/thinking_toggle.dart';
import 'package:oh_my_llm/features/settings/application/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';

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

    expect(find.text('模型选择器'), findsNothing);
    expect(find.text('前置 Prompt 选择器'), findsNothing);
    expect(find.text('消息定位条'), findsNothing);
    expect(find.byKey(const ValueKey('message-anchor-rail')), findsNothing);
    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.text('未命名对话'), findsOneWidget);
    expect(find.textContaining('深度思考：'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(SegmentedButton<ReasoningEffort>), findsNothing);
    // ThinkingToggle 现在是纯 pill，不含 Switch
    expect(find.byType(Switch), findsNothing);
    // 思考强度 pill 通过 PopupMenuButton tooltip 可被查找
    expect(find.byTooltip('思考强度'), findsOneWidget);
  });

  testWidgets('chat screen prefers default model for reasoning capability', (
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
          'selectedModelId': 'model-legacy',
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

    expect(find.text('固定顺序提示词'), findsOneWidget);
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

    expect(find.byTooltip('滚动到底部'), findsNothing);
    expect(find.textContaining('第 8 条回复'), findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('滚动到底部'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 8 条回复'), findsWidgets);
    expect(find.byTooltip('滚动到底部'), findsNothing);
  });

  testWidgets(
    'chat screen uses the latest default Prompt for an existing conversation',
    (tester) async {
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

      await sendMessage(tester, '第一次问题');
      await tester.pumpAndSettle();
      expect(fakeClient.requestHistory.first.first.content, '模板一前置');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container
          .read(chatDefaultsProvider.notifier)
          .setDefaultPromptTemplateId('prompt-2');
      await tester.pumpAndSettle();

      await sendMessage(tester, '第二次问题');
      await tester.pumpAndSettle();

      final lastRequestContents = fakeClient.requestHistory.last
          .map((message) => message.content)
          .toList(growable: false);
      expect(lastRequestContents.first, '模板二前置');
      expect(lastRequestContents, isNot(contains('模板一前置')));
    },
  );

  testWidgets(
    'chat screen does not fall back to a stale conversation Prompt after clearing the default',
    (tester) async {
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

      await sendMessage(tester, '第一次问题');
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container
          .read(chatDefaultsProvider.notifier)
          .setDefaultPromptTemplateId(null);
      await tester.pumpAndSettle();

      await sendMessage(tester, '第二次问题');
      await tester.pumpAndSettle();

      final lastRequestContents = fakeClient.requestHistory.last
          .map((message) => message.content)
          .toList(growable: false);
      expect(lastRequestContents, ['第一次问题', '第一次回复', '第二次问题']);
    },
  );
}
