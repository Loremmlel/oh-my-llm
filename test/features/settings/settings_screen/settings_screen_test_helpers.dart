import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

Future<void> pumpSettingsScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
}) async {
  tester.view.physicalSize = const Size(1440, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );

  await tester.pumpAndSettle();
}

Future<SharedPreferences> createEmptyPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

Future<SharedPreferences> createDefaultsSeededPreferences() async {
  SharedPreferences.setMockInitialValues({
    llmModelConfigsStorageKey: jsonEncode([
      {
        'id': 'model-1',
        'displayName': 'OpenAI 4.1',
        'apiUrl': 'https://api.example.com/v1/chat/completions',
        'apiKey': 'sk-test-12345678',
        'modelName': 'gpt-4.1',
        'supportsReasoning': true,
      },
      {
        'id': 'model-2',
        'displayName': 'Claude Sonnet',
        'apiUrl': 'https://api.example.com/v1/chat/completions',
        'apiKey': 'sk-test-87654321',
        'modelName': 'claude-sonnet',
        'supportsReasoning': false,
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
  return SharedPreferences.getInstance();
}
