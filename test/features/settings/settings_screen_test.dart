import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('settings screen supports model config CRUD with persistence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1440, 1024);
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
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    await tester.pumpAndSettle();

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

    expect(find.text('OpenAI 4.1'), findsOneWidget);
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

    expect(find.text('OpenAI 4.1 Turbo'), findsOneWidget);
    expect(
      preferences.getString(llmModelConfigsStorageKey),
      contains('OpenAI 4.1 Turbo'),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有模型配置'), findsOneWidget);
    expect(
      preferences.getString(llmModelConfigsStorageKey),
      equals('[]'),
    );
  });

  testWidgets('settings screen supports prompt template CRUD with persistence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1440, 1024);
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
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    await tester.pumpAndSettle();

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

    expect(find.text('代码审阅'), findsOneWidget);
    expect(
      preferences.getString(promptTemplatesStorageKey),
      contains('代码审阅'),
    );
    expect(find.textContaining('1 条 system 指令 + 1 条附加消息'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '代码审阅 v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('代码审阅 v2'), findsOneWidget);
    expect(
      preferences.getString(promptTemplatesStorageKey),
      contains('代码审阅 v2'),
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有 Prompt 模板'), findsOneWidget);
    expect(
      preferences.getString(promptTemplatesStorageKey),
      equals('[]'),
    );
  });
}
