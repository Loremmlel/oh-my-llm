import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
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

    fakeClient.emit('第一段 ');
    await tester.pump();

    expect(find.textContaining('第一段'), findsWidgets);
    expect(find.text('流式生成中'), findsOneWidget);

    fakeClient.emit('第二段');
    await fakeClient.close();
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

class FakeChatCompletionClient implements ChatCompletionClient {
  final StreamController<String> _controller = StreamController<String>();

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
    return _controller.stream;
  }

  void emit(String chunk) {
    _controller.add(chunk);
  }

  Future<void> close() {
    return _controller.close();
  }
}
