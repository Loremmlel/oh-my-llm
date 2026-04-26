import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';

void main() {
  testWidgets('chat screen shows core workspace controls', (tester) async {
    final preferences = await _createSeededPreferences();

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

  testWidgets('chat screen sends message and derives conversation title', (
    tester,
  ) async {
    final preferences = await _createSeededPreferences();

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
    await tester.pumpAndSettle();

    expect(find.textContaining('帮我总结一下这个仓库'), findsWidgets);
    expect(find.text('已收到你的输入'), findsOneWidget);
    expect(find.textContaining('帮我总结一下这个仓'), findsWidgets);
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
