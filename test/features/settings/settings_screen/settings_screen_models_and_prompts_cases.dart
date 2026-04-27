import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets('settings screen supports model config CRUD with persistence', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(tester, preferences: preferences);

    expect(find.text('还没有模型配置'), findsOneWidget);

    await tester.tap(find.text('新增模型'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'OpenAI 4.1');
    await tester.enterText(
      fields.at(1),
      'https://api.example.com/v1/chat/completions',
    );
    await tester.enterText(fields.at(2), 'sk-test-12345678');
    await tester.enterText(fields.at(3), 'gpt-4.1');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI 4.1'), findsWidgets);
    expect(
      preferences.getString(llmModelConfigsStorageKey),
      contains('OpenAI 4.1'),
    );
    expect(find.text('支持深度思考'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(0), 'OpenAI 4.1 Turbo');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI 4.1 Turbo'), findsWidgets);
    expect(
      preferences.getString(llmModelConfigsStorageKey),
      contains('OpenAI 4.1 Turbo'),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有模型配置'), findsOneWidget);
    expect(preferences.getString(llmModelConfigsStorageKey), contains('"items":[]'));
  });

  testWidgets(
    'settings screen supports prompt template CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      // 接收数据库实例以便查询 SQLite 断言。
      final database = await pumpSettingsScreen(tester, preferences: preferences);
      final repo = SqlitePromptTemplateRepository(database);

      expect(find.text('还没有 Prompt 模板'), findsOneWidget);

      await tester.tap(find.text('新增模板'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '代码审阅');
      await tester.enterText(fields.at(1), '你是资深代码审阅助手。');
      await tester.tap(find.text('新增 User'));
      await tester.pumpAndSettle();

      final dialogFields = find.byType(TextFormField);
      await tester.enterText(dialogFields.at(2), '请检查这段代码的边界情况。');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('代码审阅'), findsWidgets);
      expect(repo.loadAll().any((t) => t.name == '代码审阅'), isTrue);
      expect(find.textContaining('1 条 system 指令 + 1 条附加消息'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '代码审阅 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('代码审阅 v2'), findsWidgets);
      expect(repo.loadAll().any((t) => t.name == '代码审阅 v2'), isTrue);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('还没有 Prompt 模板'), findsOneWidget);
      expect(repo.loadAll(), isEmpty);
    },
  );
}
