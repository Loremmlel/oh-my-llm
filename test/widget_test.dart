import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';

import 'test_database.dart';

void main() {
  testWidgets('app bootstrap smoke test', (tester) async {
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
          'messages': const [],
          'updatedAt': '2026-04-26T00:00:00.000',
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final database = await createTestDatabase(preferences);

    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const OhMyLlmApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
  });
}
