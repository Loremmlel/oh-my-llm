import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/application/providers/model_catalog_workflow.dart';
import 'package:oh_my_llm/features/settings/data/providers/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator_provider.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/model_catalog_entry.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/lists/preset_prompts_view.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/async/widget_test_animation.dart';
import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets('创建服务商后显示协议与模型数量并持久保存', (tester) async {
    await setUpSettingsScreen(tester, size: const Size(390, 1500));
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
    expect(find.text('0 个模型 · Chat Completions'), findsOneWidget);
  });

  testWidgets('新增模型后可以直接切换表格中的思考与图像能力并保存', (tester) async {
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
    final reasoningChip = find.bySemanticsLabel('OpenAI 4.1 深度思考');
    await tester.ensureVisible(reasoningChip);
    await tester.tap(reasoningChip);
    await tester.pump();
    final imageChip = find.bySemanticsLabel('OpenAI 4.1 图像');
    await tester.tap(imageChip);
    await tester.pump();
    expect(repository.loadAll().single.supportsReasoning, isFalse);
    expect(repository.loadAll().single.supportsImageInput, isTrue);
  });

  testWidgets('批量添加直接进入 API 拉取并分别保存深度思考与图像能力', (tester) async {
    final workflow = ModelCatalogWorkflow(
      fetchModels:
          ({
            required String modelsUrl,
            required String apiKey,
            required LlmApiProtocol apiProtocol,
          }) async => const [
            ModelCatalogEntry(id: 'plain-model', ownedBy: 'vendor'),
            ModelCatalogEntry(id: 'reasoning-model', ownedBy: 'vendor'),
          ],
    );
    await setUpSettingsScreen(
      tester,
      extraOverrides: [
        modelCatalogWorkflowProvider.overrideWithValue(workflow),
      ],
    );
    final repository = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    ).read(llmModelConfigRepositoryProvider);
    await createTestProvider(tester);

    await tester.tap(find.text('批量添加'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '拉取模型'));
    await tester.pump();

    Finder modelRow(String modelName) => find.widgetWithText(Row, modelName);
    Finder selectionCheckbox(String modelName) => find
        .descendant(of: modelRow(modelName), matching: find.byType(Checkbox))
        .first;
    Finder reasoningCheckbox(String modelName) => find.descendant(
      of: modelRow(modelName),
      matching: find.byWidgetPredicate(
        (widget) => widget is Checkbox && widget.semanticLabel == '深度思考',
      ),
    );

    await tester.tap(selectionCheckbox('plain-model'));
    await tester.pump();
    await tester.tap(selectionCheckbox('reasoning-model'));
    await tester.pump();
    await tester.tap(reasoningCheckbox('reasoning-model'));
    await tester.tap(
      find.descendant(
        of: modelRow('reasoning-model'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Checkbox && widget.semanticLabel == '图像',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('添加所选模型'));
    await settleOverlayTransition(tester);

    final models = repository.loadAll();
    expect(
      models
          .singleWhere((model) => model.modelName == 'reasoning-model')
          .supportsImageInput,
      isTrue,
    );
    expect(
      models
          .singleWhere((model) => model.modelName == 'plain-model')
          .supportsImageInput,
      isFalse,
    );
    expect(
      models
          .singleWhere((model) => model.modelName == 'plain-model')
          .supportsReasoning,
      isFalse,
    );
    expect(
      models
          .singleWhere((model) => model.modelName == 'reasoning-model')
          .supportsReasoning,
      isTrue,
    );
  });

  testWidgets('服务商模型默认折叠，展开后可查看模型名称', (tester) async {
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

    await tester.tap(find.byTooltip('展开模型（2）'));
    await tester.pump();

    expect(find.textContaining('gpt-4.1'), findsOneWidget);
  });

  testWidgets('复制预设到剪贴板生成仅含预设的当前格式文档', (tester) async {
    final clipboardWrites = <String>[];
    await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      clipboardWrites: clipboardWrites,
      presetPrompts: [
        TestFixtures.presetPrompt(id: 'preset-seeded', name: '代码审阅'),
      ],
    );

    // 锚定「代码审阅」记录的操作，避免同名控件干扰。
    final copyButton = find.descendant(
      of: find.ancestor(
        of: find.text('代码审阅'),
        matching: find.byType(PresetPromptRow),
      ),
      matching: find.widgetWithText(TextButton, '复制'),
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

  testWidgets('设置页预设开关持久保存且编辑条目不重置开关', (tester) async {
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
    expect(find.text('2 条'), findsOneWidget);
    final saved = presetPromptRepository.loadAll(database).single;
    expect(saved.singleSystemPrompt, isFalse);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(
      presetPromptRepository.loadAll(database).single.singleSystemPrompt,
      isTrue,
    );
    await tester.tap(find.widgetWithText(TextButton, '编辑'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('保存'));
    await settleOverlayTransition(tester);
    expect(
      presetPromptRepository.loadAll(database).single.singleSystemPrompt,
      isTrue,
    );
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(
      presetPromptRepository.loadAll(database).single.singleSystemPrompt,
      isFalse,
    );
  });

  testWidgets('窄屏预设记录的单 System 开关可切换且无溢出', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      size: const Size(390, 844),
      initialTabIndex: 1,
      presetPrompts: [
        TestFixtures.presetPrompt(id: 'narrow-preset', name: '窄屏预设'),
      ],
    );
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(
      presetPromptRepository.loadAll(database).single.singleSystemPrompt,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('预设删除可取消且确认后才移除记录', (tester) async {
    final database = await setUpSettingsScreen(
      tester,
      initialTabIndex: 1,
      presetPrompts: [
        TestFixtures.presetPrompt(id: 'delete-preset', name: '待删除预设'),
      ],
    );
    Future<void> openDelete() async {
      await tester.tap(find.byTooltip('预设操作'));
      await settleOverlayTransition(tester);
      await tester.tap(find.text('删除'));
      await settleOverlayTransition(tester);
    }

    await openDelete();
    expect(find.textContaining('已有聊天记录会保留'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(presetPromptRepository.loadAll(database), hasLength(1));
    await openDelete();
    await tester.tap(find.widgetWithText(FilledButton, '删除预设'));
    await settleOverlayTransition(tester);
    expect(presetPromptRepository.loadAll(database), isEmpty);
    expect(find.text('还没有预设 Prompt'), findsOneWidget);
  });

  testWidgets('预设条目插入选中项之后，保存正文与注入位置顺序', (tester) async {
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
    expect(savedMessages.map((message) => message.content), [
      '内容1',
      '内容1.5',
      '内容2',
    ]);
    expect(savedMessages.last.placement.name, 'after');
    expect(find.text('插入测试模板'), findsWidgets);
  });

  testWidgets('创建模板提示词保存变量默认值并显示新模板', (tester) async {
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

  testWidgets('创建记忆提示词持久保存名称与正文', (tester) async {
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
