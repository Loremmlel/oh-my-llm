import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_template_prompt_repository.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets(
    'settings screen supports provider and model CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(tester, preferences: preferences);

      expect(find.text('还没有服务商配置'), findsOneWidget);

      await tester.tap(find.text('新增服务商'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OpenAI 官方');
      await tester.enterText(
        fields.at(1),
        'https://api.example.com/v1/chat/completions',
      );
      await tester.enterText(fields.at(2), 'sk-test-12345678');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 官方'), findsWidgets);
      expect(
        preferences.getString(llmModelConfigsStorageKey),
        contains('OpenAI 官方'),
      );
      expect(find.text('当前服务商下还没有模型。'), findsOneWidget);

      await tester.tap(find.text('新增模型'));
      await tester.pumpAndSettle();

      final modelFields = find.byType(TextFormField);
      await tester.enterText(modelFields.at(0), 'OpenAI 4.1');
      await tester.enterText(modelFields.at(1), 'gpt-4.1');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 4.1'), findsWidgets);
      expect(find.text('支持深度思考'), findsOneWidget);
      expect(
        preferences.getString(llmModelConfigsStorageKey),
        contains('gpt-4.1'),
      );

      await tester.tap(find.text('编辑服务商'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'OpenAI 官方 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 官方 v2'), findsWidgets);
      expect(
        preferences.getString(llmModelConfigsStorageKey),
        contains('OpenAI 官方 v2'),
      );

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'OpenAI 4.1 Turbo',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 4.1 Turbo'), findsWidgets);
      expect(
        preferences.getString(llmModelConfigsStorageKey),
        contains('OpenAI 4.1 Turbo'),
      );

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('当前服务商下还没有模型。'), findsOneWidget);

      await tester.tap(find.text('删除服务商'));
      await tester.pumpAndSettle();

      expect(find.text('还没有服务商配置'), findsOneWidget);
      expect(
        preferences.getString(llmModelConfigsStorageKey),
        contains('"items":[]'),
      );
    },
  );

  testWidgets(
    'settings screen stacks provider and model actions on narrow layouts',
    (tester) async {
      final preferences = await createDefaultsSeededPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
      );

      final providerMetaRect = tester.getRect(find.text('模型数量：1').first);
      final addModelButtonRect = tester.getRect(find.text('新增模型').first);
      expect(addModelButtonRect.top, greaterThan(providerMetaRect.bottom));

      final modelMetaRect = tester.getRect(find.text('API 模型名称：gpt-4.1'));
      final editModelButtonRect = tester.getRect(find.text('编辑').first);
      expect(editModelButtonRect.top, greaterThan(modelMetaRect.bottom));
    },
  );

  testWidgets(
    'settings screen supports prompt template CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      // 接收数据库实例以便查询 SQLite 断言。
      final database = await pumpSettingsScreen(
        tester,
        preferences: preferences,
      );
      final repo = SqlitePromptTemplateRepository(database);

      expect(find.text('还没有预设 Prompt'), findsOneWidget);

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('preset-prompt-form-layout')),
        findsOneWidget,
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '代码审阅');
      await tester.tap(find.text('新增条目'));
      await tester.pumpAndSettle();

      final dialogFields = find.byType(TextFormField);
      await tester.enterText(dialogFields.at(1), '前置要求');
      await tester.enterText(dialogFields.at(2), '请检查这段代码的边界情况。');
      await tester.tap(
        find.byKey(const ValueKey('preset-prompt-placement-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('后置').last);
      await tester.pumpAndSettle();
      expect(find.text('后置 前置要求'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('代码审阅'), findsWidgets);
      expect(repo.loadAll().any((t) => t.name == '代码审阅'), isTrue);
      expect(repo.loadAll().single.messages.single.title, '前置要求');
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

      expect(find.text('还没有预设 Prompt'), findsOneWidget);
      expect(repo.loadAll(), isEmpty);
    },
  );

  testWidgets(
    'settings screen supports template prompt CRUD with persistence',
    (tester) async {
      final preferences = await createEmptyPreferences();

      final database = await pumpSettingsScreen(
        tester,
        preferences: preferences,
      );
      final repo = SqliteTemplatePromptRepository(database);

      expect(find.text('还没有模板提示词'), findsOneWidget);

      await tester.tap(find.text('新增模板提示词'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '翻译模板');
      await tester.enterText(fields.at(1), '请把{{正文}}翻译成{{目标语言}}。');
      await tester.pumpAndSettle();

      expect(find.text('正文 使用聊天页主输入框提供内容，不单独设置默认值。'), findsOneWidget);

      final refreshedFields = find.byType(TextFormField);
      await tester.enterText(refreshedFields.at(2), '英文');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('翻译模板'), findsWidgets);
      expect(repo.loadAll().any((item) => item.title == '翻译模板'), isTrue);
      expect(find.textContaining('共 2 个变量'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '翻译模板 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('翻译模板 v2'), findsWidgets);
      expect(repo.loadAll().any((item) => item.title == '翻译模板 v2'), isTrue);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('还没有模板提示词'), findsOneWidget);
      expect(repo.loadAll(), isEmpty);
    },
  );

  testWidgets('settings screen supports memory prompt CRUD with persistence', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    final database = await pumpSettingsScreen(tester, preferences: preferences);
    final repo = SqliteMemoryPromptRepository(database);

    expect(find.text('还没有记忆总结提示词'), findsOneWidget);

    await tester.tap(find.text('新增记忆提示词'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '研发任务总结');
    await tester.enterText(fields.at(1), '请总结当前研发任务中的决定、约束与待办。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('研发任务总结'), findsWidgets);
    expect(repo.loadAll().any((item) => item.name == '研发任务总结'), isTrue);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '研发任务总结 v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('研发任务总结 v2'), findsWidgets);
    expect(repo.loadAll().any((item) => item.name == '研发任务总结 v2'), isTrue);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有记忆总结提示词'), findsOneWidget);
    expect(repo.loadAll(), isEmpty);
  });
}
