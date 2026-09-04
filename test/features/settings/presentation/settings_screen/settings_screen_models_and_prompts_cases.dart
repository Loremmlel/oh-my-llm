import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_entity_card.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/async/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets('settings screen creates a provider and verifies persistence', (
    tester,
  ) async {
    await setUpSettingsScreen(tester);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);
    expect(repository.loadProviders(), isEmpty);

    await tester.tap(find.text('新增服务商'));
    await settleOverlayTransition(tester);

    await tester.enterText(providerNameField(), 'OpenAI 官方');
    await tester.enterText(
      providerApiUrlField(),
      'https://api.example.com/v1/chat/completions',
    );
    await tester.enterText(providerApiKeyField(), 'sk-test-12345678');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdProvider = repository.loadProviders().single;
    expect(createdProvider.name, 'OpenAI 官方');
    expect(repository.loadAll(), isEmpty);
    expect(find.text('OpenAI 官方'), findsWidgets);
    expect(find.text('协议：Chat Completions'), findsOneWidget);
  });

  testWidgets('settings screen creates a model under a provider', (
    tester,
  ) async {
    await setUpSettingsScreen(tester);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);

    await createTestProvider(tester);

    await tester.tap(find.text('新增模型'));
    await settleOverlayTransition(tester);

    await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
    await tester.enterText(modelApiNameField(), 'gpt-4.1');
    await tester.tap(modelSupportsReasoningField());
    // 开关切换只改表单状态，动画纯视觉，单帧即可
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdModel = repository.loadAll().single;
    expect(createdModel.displayName, 'OpenAI 4.1');
    expect(createdModel.modelName, 'gpt-4.1');
    expect(createdModel.supportsReasoning, isTrue);
    expect(find.text('OpenAI 4.1'), findsWidgets);
  });

  testWidgets(
    'settings screen keeps model list collapsed by default and expands on demand',
    (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final preferences = await createDefaultsSeededPreferences(database);

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        database: database,
        size: const Size(430, 932),
      );

      expect(find.textContaining('gpt-4.1'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, '展开模型（2）'));
      // 模型列表展开是 AnimatedSize 动画
      await settleAnimatedWidgetTransition(tester);

      expect(find.textContaining('gpt-4.1'), findsOneWidget);
    },
  );

  testWidgets('settings screen creates a prompt template', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: 1,
    );
    final repository = presetPromptRepository;
    expect(repository.loadAll(database), isEmpty);

    await tester.tap(find.text('新增预设'));
    await settleOverlayTransition(tester);
    await tester.enterText(presetPromptNameField(), '代码审阅');
    await tester.tap(find.text('新增条目'));
    // 条目插入是 setState 直改列表，无动画
    await tester.pump();

    await tester.enterText(presetPromptTitleField(), '前置要求');
    await tester.enterText(presetPromptContentField(), '请检查这段代码的边界情况。');
    await tester.tap(find.text('前置'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('后置').last);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdTemplate = repository.loadAll(database).single;
    expect(createdTemplate.name, '代码审阅');
    expect(createdTemplate.messages, hasLength(1));
    expect(createdTemplate.messages.single.title, '前置要求');
    expect(createdTemplate.messages.single.content, '请检查这段代码的边界情况。');
    expect(find.text('代码审阅'), findsWidgets);
  });

  testWidgets('复制预设到剪贴板生成仅含预设的 v9 文档', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      clipboardWrites: clipboardWrites,
      presetPrompts: [
        TestFixtures.presetPrompt(id: 'preset-seeded', name: '代码审阅'),
      ],
    );

    // 锚定「代码审阅」卡片上的「复制」按钮：避免被同名的其它控件干扰。
    final copyButton = find.descendant(
      of: find.ancestor(
        of: find.text('代码审阅'),
        matching: find.byType(SettingsEntityCard),
      ),
      matching: find.widgetWithText(OutlinedButton, '复制'),
    );
    await tester.tap(copyButton);
    // 复制是直接 Future（写剪贴板 + 提示），单帧即可。
    await tester.pump();

    expect(clipboardWrites, hasLength(1));
    final decoded = SettingsTransferDocumentCodec.decodeJson(
      clipboardWrites.single,
    );
    expect(decoded, isA<SettingsTransferDocumentDecodeSuccess>());
    final document =
        (decoded as SettingsTransferDocumentDecodeSuccess).document;
    expect(document.sections.keys, ['presetPrompts']);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container
          .read(settingsTransferCoordinatorProvider)
          .prepareJson(clipboardWrites.single),
      isA<SettingsImportNoChanges>(),
    );
    expect(find.text('已复制预设 Prompt 到剪贴板'), findsOneWidget);
    expect(find.textContaining('（副本'), findsNothing);
  });

  testWidgets('prompt template dialog accepts multiple system messages', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: 1,
    );

    await tester.tap(find.text('新增预设'));
    await settleOverlayTransition(tester);
    await tester.enterText(presetPromptNameField(), '多 system 模板');

    Future<void> fillItem({
      required String title,
      required String content,
      required String roleLabel,
    }) async {
      await tester.tap(find.text('新增条目'));
      // 条目插入是 setState 直改列表，无动画
      await tester.pump();
      await tester.enterText(presetPromptTitleField(), title);
      await tester.enterText(presetPromptContentField(), content);
      await tester.tap(find.text('User'));
      await settleOverlayTransition(tester);
      await tester.tap(find.text(roleLabel).last);
      await settleOverlayTransition(tester);
    }

    await fillItem(title: '系统 1', content: '系统内容 1', roleLabel: 'System');
    await fillItem(title: '系统 2', content: '系统内容 2', roleLabel: 'System');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(find.text('多 system 模板'), findsWidgets);
    expect(find.textContaining('共 2 条消息'), findsOneWidget);
  });

  testWidgets(
    'prompt template dialog inserts below selection and persists order',
    (tester) async {
      final database = await setUpSettingsScreen(
        tester,
        size: const Size(1440, 2200),
        initialTabIndex: 1,
      );
      final addItemButton = find.widgetWithText(OutlinedButton, '新增条目');

      Future<void> fillSelectedItem(String title, String content) async {
        await tester.enterText(presetPromptTitleField(), title);
        await tester.enterText(presetPromptContentField(), content);
        await tester.pump();
      }

      await tester.tap(find.text('新增预设'));
      await settleOverlayTransition(tester);
      await tester.enterText(presetPromptNameField(), '插入测试模板');

      await tester.tap(addItemButton);
      await tester.pump();
      await fillSelectedItem('前置1', '内容1');

      await tester.tap(addItemButton);
      await tester.pump();
      await fillSelectedItem('后置1', '内容2');

      await tester.tap(find.text('前置'));
      await settleOverlayTransition(tester);
      await tester.tap(find.text('后置').last);
      await settleOverlayTransition(tester);

      await tester.tap(find.text('前置1').hitTestable());
      await tester.pump();
      await tester.tap(addItemButton);
      await tester.pump();
      await fillSelectedItem('前置1.5', '内容1.5');
      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      final savedMessages = presetPromptRepository
          .loadAll(database)
          .single
          .messages;
      expect(savedMessages.map((message) => message.title), [
        '前置1',
        '前置1.5',
        '后置1',
      ]);
    },
  );

  testWidgets('settings screen creates a template prompt', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: 2,
    );
    final repository = templatePromptRepository;
    expect(repository.loadAll(database), isEmpty);

    await tester.tap(find.text('新增模板提示词'));
    await settleOverlayTransition(tester);

    await tester.enterText(templatePromptTitleField(), '翻译模板');
    await tester.enterText(
      templatePromptContentField(),
      '请把{{正文}}翻译成{{目标语言}}。',
    );
    // 精确推进防抖常量，变量重算恰好触发，无需 +50ms 余量
    await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce);
    await tester.pump();

    await tester.enterText(templatePromptVariableField('目标语言'), '英文');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdTemplate = repository.loadAll(database).single;
    expect(createdTemplate.title, '翻译模板');
    expect(createdTemplate.variables.map((variable) => variable.name), [
      templatePromptBodyVariableName,
      '目标语言',
    ]);
    expect(createdTemplate.variables.last.defaultValue, '英文');
    expect(find.text('翻译模板'), findsWidgets);
  });

  testWidgets('template prompt variable reconcile uses debounce', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: 2,
    );

    await tester.tap(find.text('新增模板提示词'));
    await settleOverlayTransition(tester);

    await tester.enterText(templatePromptTitleField(), '防抖测试');
    await tester.enterText(templatePromptContentField(), '请处理{{变量A}}。');
    // 仅 pump 一帧（0ms），防抖 220ms 未到，变量不出现。
    await tester.pump();
    expect(find.text('变量A'), findsNothing);

    // 精确推进公开常量 220ms，防抖窗口恰好结束，变量出现。
    await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce);
    await tester.pump();
    expect(find.text('变量A'), findsOneWidget);

    // 替换为另一变量，未到防抖窗口时仍显示旧变量。
    await tester.enterText(templatePromptContentField(), '请处理{{变量B}}。');
    await tester.pump();
    expect(find.text('变量A'), findsOneWidget);
    expect(find.text('变量B'), findsNothing);

    // 精确推进防抖窗口后切换到新变量。
    await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce);
    await tester.pump();
    expect(find.text('变量A'), findsNothing);
    expect(find.text('变量B'), findsOneWidget);
  });

  testWidgets('settings screen creates a memory prompt', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: 2,
    );
    final repository = memoryPromptRepository;
    expect(repository.loadAll(database), isEmpty);

    await tester.tap(find.text('新增记忆提示词'));
    await settleOverlayTransition(tester);

    await tester.enterText(memoryPromptNameField(), '研发任务总结');
    await tester.enterText(memoryPromptContentField(), '请总结当前研发任务中的决定、约束与待办。');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdPrompt = repository.loadAll(database).single;
    expect(createdPrompt.name, '研发任务总结');
    expect(createdPrompt.content, '请总结当前研发任务中的决定、约束与待办。');
    expect(find.text('研发任务总结'), findsWidgets);
  });
}
