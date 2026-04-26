import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  testWidgets('chat screen shows core workspace controls', (tester) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('模型选择器'), findsOneWidget);
    expect(find.text('前置 Prompt 选择器'), findsOneWidget);
    expect(find.text('消息定位条'), findsOneWidget);
    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.text('未命名对话'), findsOneWidget);
    expect(find.textContaining('深度思考：'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(SegmentedButton<ReasoningEffort>), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('思考负担'), findsOneWidget);
  });

  testWidgets('chat screen renames conversation without controller errors', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

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

  testWidgets('chat screen streams reply and updates anchors/history', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    fakeClient.enqueueChunks(
      ['第一段 ', '第二段'],
      chunkDelay: const Duration(milliseconds: 10),
    );

    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '帮我总结一下这个仓库的结构和当前能力',
    );
    final sendButton = find.widgetWithText(FilledButton, '发送');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 12));

    expect(find.textContaining('第一段'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '生成中'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.textContaining('帮我总结一下这个仓库'), findsWidgets);
    expect(find.textContaining('第一段 第二段'), findsWidgets);
    expect(find.textContaining('帮我总结一下这个仓'), findsWidgets);
    expect(find.text('— 1'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(
      fakeClient.lastRequestMessages.map((message) => message.role).toList(),
      [ChatMessageRole.user],
    );
    expect(
      fakeClient.lastRequestMessages.single.content,
      '帮我总结一下这个仓库的结构和当前能力',
    );
    expect(
      fakeClient.lastModelConfig?.displayName,
      equals('GPT-4.1'),
    );
  });

  testWidgets('chat screen edits user message and regenerates following replies', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复一'])
      ..enqueueChunks(['原始回复二']);

    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await _sendMessage(tester, '第一条原始问题');
    await tester.pumpAndSettle();
    await _sendMessage(tester, '第二条问题');
    await tester.pumpAndSettle();

    fakeClient
      ..enqueueChunks(['重算后的回复一'])
      ..enqueueChunks(['重算后的回复二']);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final activeConversation = container.read(chatSessionsProvider).activeConversation;
    final firstUserMessage = activeConversation.messages.firstWhere((message) {
      return message.role == ChatMessageRole.user;
    });

    await container.read(chatSessionsProvider.notifier).editMessage(
          messageId: firstUserMessage.id,
          nextContent: '第一条已修改问题',
        );
    await tester.pumpAndSettle();

    expect(find.textContaining('第一条已修改问题'), findsWidgets);
    expect(find.textContaining('重算后的回复一'), findsWidgets);
    expect(find.textContaining('重算后的回复二'), findsWidgets);
    expect(find.textContaining('原始回复一'), findsNothing);
    expect(find.textContaining('原始回复二'), findsNothing);
    expect(
      fakeClient.requestHistory[2].map((message) => message.content).toList(),
      ['第一条已修改问题'],
    );
    expect(
      fakeClient.requestHistory[3].map((message) => message.content).toList(),
      ['第一条已修改问题', '重算后的回复一', '第二条问题'],
    );
  });

  testWidgets('chat screen retries latest assistant reply', (tester) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['原始回复'])
      ..enqueueChunks(['重试后的回复']);

    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await _sendMessage(tester, '帮我重试一下');
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

  testWidgets('chat screen keeps composer visible on compact layouts', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsNothing);
    expect(find.widgetWithText(FilledButton, '发送').hitTestable(), findsOneWidget);
  });
}

Future<SharedPreferences> _createSeededPreferences() async {
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
        'name': '代码助手',
        'systemPrompt': '你是代码助手',
        'messages': [
          {
            'id': 'message-1',
            'role': 'user',
            'content': '请优先关注实现细节。',
          },
        ],
        'updatedAt': DateTime(2026, 4, 26).toIso8601String(),
      },
    ]),
  });

  return SharedPreferences.getInstance();
}

Future<void> _sendMessage(WidgetTester tester, String content) async {
  await tester.enterText(find.byType(TextField).first, content);
  final sendButton = find.widgetWithText(FilledButton, '发送');
  await tester.ensureVisible(sendButton);
  await tester.tap(sendButton);
  await tester.pump();
}

class FakeChatCompletionClient implements ChatCompletionClient {
  final List<List<ChatCompletionRequestMessage>> requestHistory = [];
  final List<LlmModelConfig> requestedModels = [];
  final List<Stream<String>> _queuedStreams = [];

  List<ChatCompletionRequestMessage> lastRequestMessages = const [];
  LlmModelConfig? lastModelConfig;

  @override
  Stream<String> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) {
    lastModelConfig = modelConfig;
    lastRequestMessages = List.unmodifiable(messages);
    requestHistory.add(lastRequestMessages);
    requestedModels.add(modelConfig);
    if (_queuedStreams.isEmpty) {
      return const Stream.empty();
    }

    return _queuedStreams.removeAt(0);
  }

  void enqueueChunks(
    List<String> chunks, {
    Duration chunkDelay = Duration.zero,
  }) {
    _queuedStreams.add(_streamChunks(chunks, chunkDelay));
  }

  Stream<String> _streamChunks(List<String> chunks, Duration chunkDelay) async* {
    for (final chunk in chunks) {
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
      yield chunk;
    }
  }
}
