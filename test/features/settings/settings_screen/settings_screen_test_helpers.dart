import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../../../test_database.dart';

/// 挂载设置页并返回测试用数据库实例，供断言查询 SQLite 数据。
Future<AppDatabase> pumpSettingsScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
}) async {
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
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return database;
}

Future<SharedPreferences> createEmptyPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

/// 创建包含默认种子数据的 SharedPreferences 实例。
///
/// 模型配置继续存储在 SP 中；Prompt 模板以旧版格式写入 SP，
/// 在 [pumpSettingsScreen] 内调用的迁移逻辑会将其搬到 SQLite。
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
    // Prompt 模板以旧版 SP 格式写入，由迁移流程搬到 SQLite。
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
