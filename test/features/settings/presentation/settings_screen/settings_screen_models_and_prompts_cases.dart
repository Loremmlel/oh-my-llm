import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_entity_card.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/async/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

LlmModelConfig _seededModel({
  LlmApiProtocol protocol = LlmApiProtocol.chatCompletions,
}) => LlmModelConfig(
  id: 'model-seeded',
  displayName: 'OpenAI 4.1',
  modelName: 'gpt-4.1',
  supportsReasoning: false,
  apiUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'sk-test-12345678',
  providerId: 'provider-seeded',
  providerName: 'OpenAI 官方',
  apiProtocol: protocol,
);

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

  testWidgets('settings screen saves selected protocol and shows it', (
    tester,
  ) async {
    await setUpSettingsScreen(tester);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);

    await tester.tap(find.text('新增服务商'));
    await settleOverlayTransition(tester);
    await tester.enterText(providerNameField(), 'OpenAI 官方');
    await tester.enterText(
      providerApiUrlField(),
      'https://api.example.com/v1/chat/completions',
    );
    await tester.enterText(providerApiKeyField(), 'sk-test-12345678');
    await selectProviderProtocol(tester, LlmApiProtocol.responses);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final createdProvider = repository.loadProviders().single;
    expect(createdProvider.apiProtocol, LlmApiProtocol.responses);
    expect(find.text('协议：Responses'), findsOneWidget);
  });

  testWidgets('settings screen applies edited protocol to all models', (
    tester,
  ) async {
    await setUpSettingsScreen(tester, models: [_seededModel()]);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);

    // 编辑服务商切换到 Anthropic：协议变更立即作用于全部模型。
    await tester.tap(find.text('编辑服务商'));
    await settleOverlayTransition(tester);
    await selectProviderProtocol(tester, LlmApiProtocol.anthropic);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final editedProvider = repository.loadProviders().single;
    expect(editedProvider.apiProtocol, LlmApiProtocol.anthropic);
    expect(editedProvider.models.single.id, isNotEmpty);
    expect(editedProvider.models.single.modelName, 'gpt-4.1');
    expect(
      editedProvider.models.single
          .resolveForProvider(editedProvider)
          .apiProtocol,
      LlmApiProtocol.anthropic,
    );
    expect(find.text('协议：Anthropic'), findsOneWidget);
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

  testWidgets('settings screen edits provider and model names', (tester) async {
    await setUpSettingsScreen(tester, models: [_seededModel()]);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);

    await tester.tap(find.text('编辑服务商'));
    await settleOverlayTransition(tester);
    await tester.enterText(providerNameField(), 'OpenAI 官方 v2');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    expect(repository.loadProviders().single.name, 'OpenAI 官方 v2');
    expect(find.text('OpenAI 官方 v2'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '展开模型（1）'));
    await settleAnimatedWidgetTransition(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '编辑'));
    await settleOverlayTransition(tester);
    await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1 Turbo');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    expect(repository.loadAll().single.displayName, 'OpenAI 4.1 Turbo');
    expect(find.text('OpenAI 4.1 Turbo'), findsWidgets);
  });

  testWidgets('settings screen deletes model then provider', (tester) async {
    await setUpSettingsScreen(tester, models: [_seededModel()]);
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);

    await tester.tap(find.widgetWithText(OutlinedButton, '展开模型（1）'));
    await settleAnimatedWidgetTransition(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '删除'));
    // 删除直接走 Future 链，无确认对话框，状态更新单帧即可
    await tester.pump();

    expect(repository.loadAll(), isEmpty);

    await tester.tap(find.text('删除服务商'));
    await tester.pump();

    expect(repository.loadProviders(), isEmpty);
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

  testWidgets('settings screen edits a prompt template name', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      presetPrompts: [
        TestFixtures.presetPrompt(
          id: 'preset-seeded',
          name: '代码审阅',
          messages: [
            TestFixtures.promptMessage(
              id: 'message-seeded',
              title: '前置要求',
              content: '内容',
            ).copyWith(enabled: false),
          ],
        ),
      ],
    );
    final repository = presetPromptRepository;

    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    await tester.enterText(presetPromptNameField(), '代码审阅 v2');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    final savedPrompt = repository.loadAll(database).single;
    expect(savedPrompt.name, '代码审阅 v2');
    expect(savedPrompt.messages.single.enabled, isFalse);
    expect(savedPrompt.messages.single.title, '前置要求');
    expect(find.text('代码审阅 v2'), findsWidgets);
  });

  testWidgets('settings screen deletes a prompt template', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      presetPrompts: [
        TestFixtures.presetPrompt(id: 'preset-seeded', name: '代码审阅'),
      ],
    );
    final repository = presetPromptRepository;

    await tester.tap(find.text('删除'));
    // 删除直接走 Future 链，状态更新单帧即可
    await tester.pump();

    expect(repository.loadAll(database), isEmpty);
  });

  testWidgets(
    'settings screen can duplicate prompt template with incremental suffix',
    (tester) async {
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
      await tester.enterText(presetPromptNameField(), '代码审阅');
      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      // 按原卡片标题锚定「复制」按钮：复制出的新卡片同名按钮会增多，
      // 不能依赖树序取第一个
      final duplicateButton = find.descendant(
        of: find.ancestor(
          of: find.text('代码审阅'),
          matching: find.byType(SettingsEntityCard),
        ),
        matching: find.widgetWithText(OutlinedButton, '复制'),
      );
      await tester.tap(duplicateButton);
      // 复制是直接 Future，状态更新单帧即可
      await tester.pump();
      await tester.tap(duplicateButton);
      await tester.pump();

      expect(find.text('代码审阅（副本）'), findsWidgets);
      expect(find.text('代码审阅（副本 2）'), findsWidgets);
    },
  );

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

  testWidgets('settings screen edits a template prompt title', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 2,
      templatePrompts: [
        TemplatePrompt(
          id: 'template-seeded',
          title: '翻译模板',
          content: '内容',
          variables: const [],
          updatedAt: DateTime(2026),
        ),
      ],
    );
    final repository = templatePromptRepository;

    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    await tester.enterText(templatePromptTitleField(), '翻译模板 v2');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    expect(repository.loadAll(database).single.title, '翻译模板 v2');
    expect(find.text('翻译模板 v2'), findsWidgets);
  });

  testWidgets('settings screen deletes a template prompt', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 2,
      templatePrompts: [
        TemplatePrompt(
          id: 'template-seeded',
          title: '翻译模板',
          content: '内容',
          variables: const [],
          updatedAt: DateTime(2026),
        ),
      ],
    );
    final repository = templatePromptRepository;

    await tester.tap(find.text('删除'));
    // 删除直接走 Future 链，状态更新单帧即可
    await tester.pump();

    expect(repository.loadAll(database), isEmpty);
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

  testWidgets('settings screen edits a memory prompt name', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 2,
      memoryPrompts: [
        MemoryPrompt(
          id: 'memory-seeded',
          name: '研发任务总结',
          content: '内容',
          updatedAt: DateTime(2026),
        ),
      ],
    );
    final repository = memoryPromptRepository;

    await tester.tap(find.text('编辑'));
    await settleOverlayTransition(tester);
    await tester.enterText(memoryPromptNameField(), '研发任务总结 v2');
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);

    expect(repository.loadAll(database).single.name, '研发任务总结 v2');
    expect(find.text('研发任务总结 v2'), findsWidgets);
  });

  testWidgets('settings screen deletes a memory prompt', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 2,
      memoryPrompts: [
        MemoryPrompt(
          id: 'memory-seeded',
          name: '研发任务总结',
          content: '内容',
          updatedAt: DateTime(2026),
        ),
      ],
    );
    final repository = memoryPromptRepository;

    await tester.tap(find.text('删除'));
    // 删除直接走 Future 链，状态更新单帧即可
    await tester.pump();

    expect(repository.loadAll(database), isEmpty);
  });
}
