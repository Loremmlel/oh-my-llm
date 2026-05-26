import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets(
    'settings screen supports provider and model CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();
      final repository = LlmModelConfigRepository(preferences);

      await pumpSettingsScreen(tester, preferences: preferences);
      expect(repository.loadProviders(), isEmpty);

      await tester.tap(find.text('新增服务商'));
      await tester.pumpAndSettle();

      await tester.enterText(providerNameField(), 'OpenAI 官方');
      await tester.enterText(
        providerApiUrlField(),
        'https://api.example.com/v1/chat/completions',
      );
      await tester.enterText(providerApiKeyField(), 'sk-test-12345678');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final createdProvider = repository.loadProviders().single;
      expect(createdProvider.name, 'OpenAI 官方');
      expect(repository.loadAll(), isEmpty);
      expect(find.text('OpenAI 官方'), findsWidgets);

      await tester.tap(find.text('新增模型'));
      await tester.pumpAndSettle();

      await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
      await tester.enterText(modelApiNameField(), 'gpt-4.1');
      await tester.tap(modelSupportsReasoningField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final createdModel = repository.loadAll().single;
      expect(createdModel.displayName, 'OpenAI 4.1');
      expect(createdModel.modelName, 'gpt-4.1');
      expect(createdModel.supportsReasoning, isTrue);
      expect(find.text('OpenAI 4.1'), findsWidgets);

      await tester.tap(find.text('编辑服务商'));
      await tester.pumpAndSettle();
      await tester.enterText(providerNameField(), 'OpenAI 官方 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repository.loadProviders().single.name, 'OpenAI 官方 v2');
      expect(find.text('OpenAI 官方 v2'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, '编辑').last);
      await tester.pumpAndSettle();
      await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1 Turbo');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repository.loadAll().single.displayName, 'OpenAI 4.1 Turbo');
      expect(find.text('OpenAI 4.1 Turbo'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, '删除').last);
      await tester.pumpAndSettle();

      expect(repository.loadAll(), isEmpty);

      await tester.tap(find.text('删除服务商'));
      await tester.pumpAndSettle();

      expect(repository.loadProviders(), isEmpty);
    },
  );

  testWidgets(
    'settings screen keeps model list collapsed by default and expands on demand',
    (tester) async {
      final preferences = await createDefaultsSeededPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
      );

      expect(find.textContaining('gpt-4.1'), findsNothing);

      await tester.tap(
        find.widgetWithText(OutlinedButton, '展开模型（2）'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('gpt-4.1'), findsOneWidget);
    },
  );

  testWidgets(
    'settings screen supports prompt template CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();
      final database = await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 1);
      final repository = presetPromptRepository;
      expect(repository.loadAll(database), isEmpty);

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '代码审阅');
      await tester.tap(find.text('新增条目'));
      await tester.pumpAndSettle();

      await tester.enterText(presetPromptTitleField(), '前置要求');
      await tester.enterText(
        presetPromptContentField(),
        '请检查这段代码的边界情况。',
      );
      await tester.tap(
        find.text('前置'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('后置').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final createdTemplate = repository.loadAll(database).single;
      expect(createdTemplate.name, '代码审阅');
      expect(createdTemplate.messages, hasLength(1));
      expect(createdTemplate.messages.single.title, '前置要求');
      expect(createdTemplate.messages.single.content, '请检查这段代码的边界情况。');
      expect(find.text('代码审阅'), findsWidgets);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '代码审阅 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repository.loadAll(database).single.name, '代码审阅 v2');
      expect(find.text('代码审阅 v2'), findsWidgets);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(repository.loadAll(database), isEmpty);
    },
  );

  testWidgets(
    'settings screen can duplicate prompt template with incremental suffix',
    (tester) async {
      final preferences = await createEmptyPreferences();
      await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 1);

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '代码审阅');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '复制').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '复制').first);
      await tester.pumpAndSettle();

      expect(find.text('代码审阅（副本）'), findsWidgets);
      expect(find.text('代码审阅（副本 2）'), findsWidgets);
    },
  );

  testWidgets('prompt template dialog accepts multiple system messages', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 1);

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle();
    await tester.enterText(presetPromptNameField(), '多 system 模板');

    Future<void> fillItem({
      required String title,
      required String content,
      required String roleLabel,
    }) async {
      await tester.tap(find.text('新增条目'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptTitleField(), title);
      await tester.enterText(presetPromptContentField(), content);
      await tester.tap(find.text('User'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(roleLabel).last);
      await tester.pumpAndSettle();
    }

    await fillItem(title: '系统 1', content: '系统内容 1', roleLabel: 'System');
    await fillItem(title: '系统 2', content: '系统内容 2', roleLabel: 'System');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('多 system 模板'), findsWidgets);
    expect(find.textContaining('共 2 条消息'), findsOneWidget);
  });

  testWidgets(
    'prompt template dialog inserts a new item below selection and keeps groups ordered',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
        initialTabIndex: 1,
      );
      final masterPane = find.ancestor(
        of: find.text('预设 Prompt 条目'),
        matching: find.byType(DecoratedBox),
      );
      final addItemButton = find
          .descendant(
            of: masterPane,
            matching: find.widgetWithText(OutlinedButton, '新增条目'),
          )
          .hitTestable();
      final presetList = find
          .descendant(of: masterPane, matching: find.byType(ListView))
          .hitTestable();

      Finder rawPresetTile(String title) {
        return find.descendant(of: masterPane, matching: find.text(title));
      }

      Finder presetTile(String title) {
        return rawPresetTile(title).hitTestable();
      }

      Future<void> ensurePresetTileVisible(String title) async {
        if (presetTile(title).evaluate().isNotEmpty) {
          return;
        }
        await tester.dragUntilVisible(
          rawPresetTile(title),
          presetList,
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();
      }

      Future<String> selectedTitle() async {
        final titleField = tester.widget<TextFormField>(presetPromptTitleField());
        return titleField.controller?.text ?? '';
      }

      Future<void> fillSelectedItem(String title, String content) async {
        await tester.enterText(presetPromptTitleField(), title);
        await tester.enterText(presetPromptContentField(), content);
        await tester.pump();
      }

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '插入测试模板');

      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('前置1', '内容1');

      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('后置1', '内容2');

      await tester.tap(
        find.text('前置'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('后置').last);
      await tester.pumpAndSettle();

      await tester.tap(presetTile('前置1'));
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('前置1.5', '内容1.5');
      await ensurePresetTileVisible('后置1');

      expect(
        tester.getTopLeft(rawPresetTile('前置1')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('前置1.5')).dy),
      );
      expect(
        tester.getTopLeft(rawPresetTile('前置1.5')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('后置1')).dy),
      );

      await ensurePresetTileVisible('后置1');
      await tester.tap(presetTile('后置1'));
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('后置user'));
      await fillSelectedItem('后置1.5', '内容1.5');
      await ensurePresetTileVisible('后置1.5');

      expect(
        tester.getTopLeft(rawPresetTile('后置1')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('后置1.5')).dy),
      );

    },
  );

  testWidgets(
    'prompt template dialog only keeps outer scroll on compact layout',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
        initialTabIndex: 1,
      );

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
        initialTabIndex: 1,
      );

      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      );
      final addPresetButton = find.widgetWithText(FilledButton, '新增预设');
      await tester.dragUntilVisible(
        addPresetButton,
        settingsList.first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(addPresetButton);
      await tester.pumpAndSettle();
      await tester.tap(addPresetButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('prompt template dialog keeps wide master header visible', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      size: const Size(1440, 2200),
      initialTabIndex: 1,
    );

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle();

    final masterPane = find.ancestor(
      of: find.text('预设 Prompt 条目'),
      matching: find.byType(DecoratedBox),
    );
    final addItemButton = find.descendant(
      of: masterPane,
      matching: find.widgetWithText(OutlinedButton, '新增条目'),
    );

    for (var index = 1; index <= 20; index++) {
      await tester.tap(addItemButton);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final header = find.descendant(
      of: masterPane,
      matching: find.text('预设 Prompt 条目'),
    );
    final presetList = find.descendant(
      of: masterPane,
      matching: find.byType(ListView),
    );
    final headerOffsetBefore = tester.getTopLeft(header);
    final titleField = tester.widget<TextFormField>(presetPromptTitleField());
    final latestAutoTitle = titleField.controller?.text ?? '';
    expect(latestAutoTitle, isNotEmpty);

    await tester.dragUntilVisible(
      find.text(latestAutoTitle),
      presetList,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text(latestAutoTitle), findsWidgets);
    expect(tester.getTopLeft(header).dy, headerOffsetBefore.dy);
    expect(addItemButton, findsOneWidget);
  });

  testWidgets(
    'settings screen supports template prompt CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();
      final database = await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 2);
      final repository = templatePromptRepository;
      expect(repository.loadAll(database), isEmpty);

      await tester.tap(find.text('新增模板提示词'));
      await tester.pumpAndSettle();

      await tester.enterText(templatePromptTitleField(), '翻译模板');
      await tester.enterText(
        templatePromptContentField(),
        '请把{{正文}}翻译成{{目标语言}}。',
      );
      // 等待防抖窗口（220ms）过后变量字段出现。
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      await tester.enterText(templatePromptVariableField('目标语言'), '英文');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final createdTemplate = repository.loadAll(database).single;
      expect(createdTemplate.title, '翻译模板');
      expect(createdTemplate.variables.map((variable) => variable.name), [
        templatePromptBodyVariableName,
        '目标语言',
      ]);
      expect(createdTemplate.variables.last.defaultValue, '英文');
      expect(find.text('翻译模板'), findsWidgets);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(templatePromptTitleField(), '翻译模板 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repository.loadAll(database).single.title, '翻译模板 v2');
      expect(find.text('翻译模板 v2'), findsWidgets);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(repository.loadAll(database), isEmpty);
    },
  );

  testWidgets(
    'template prompt variable reconcile uses debounce',
    (tester) async {
      final preferences = await createEmptyPreferences();
      await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 2);

      await tester.tap(find.text('新增模板提示词'));
      await tester.pumpAndSettle();

      await tester.enterText(templatePromptTitleField(), '防抖测试');
      await tester.enterText(templatePromptContentField(), '请处理{{变量A}}。');
      // 仅 pump 一帧（16ms），防抖 220ms 未到，变量不出现。
      await tester.pump();
      expect(find.text('变量A'), findsNothing);

      // pump 过防抖窗口，变量出现。
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('变量A'), findsOneWidget);

      // 替换为另一变量，未到防抖窗口时仍显示旧变量。
      await tester.enterText(templatePromptContentField(), '请处理{{变量B}}。');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('变量B'), findsNothing);

      // pump 过防抖窗口后切换到新变量。
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('变量A'), findsNothing);
      expect(find.text('变量B'), findsOneWidget);
    },
  );

  testWidgets('settings screen supports memory prompt CRUD with persistence', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    final database = await pumpSettingsScreen(tester, preferences: preferences, initialTabIndex: 2);
    final repository = memoryPromptRepository;
    expect(repository.loadAll(database), isEmpty);

    await tester.tap(find.text('新增记忆提示词'));
    await tester.pumpAndSettle();

    await tester.enterText(memoryPromptNameField(), '研发任务总结');
    await tester.enterText(
      memoryPromptContentField(),
      '请总结当前研发任务中的决定、约束与待办。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final createdPrompt = repository.loadAll(database).single;
    expect(createdPrompt.name, '研发任务总结');
    expect(createdPrompt.content, '请总结当前研发任务中的决定、约束与待办。');
    expect(find.text('研发任务总结'), findsWidgets);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(memoryPromptNameField(), '研发任务总结 v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.loadAll(database).single.name, '研发任务总结 v2');
    expect(find.text('研发任务总结 v2'), findsWidgets);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repository.loadAll(database), isEmpty);
  });

}
