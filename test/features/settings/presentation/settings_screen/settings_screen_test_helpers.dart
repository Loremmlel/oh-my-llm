import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/prompts/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/preset_editor_screen.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/fixed_prompt_sequence_editor.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/memory_prompt_editor.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_editor.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_editor.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/test_harness.dart';

const settingsLastTabIndexKey = 'settings.tab.last_index';

const tabLabels = ['服务商', '预设', '提示词', '网络', '输出处理', '其它'];

/// 切换到指定标签页；先确保 tab 在滚动区域内可见再点击。
Future<void> switchToTab(WidgetTester tester, int index) async {
  final tabFinder = find.text(tabLabels[index]);
  await tester.ensureVisible(tabFinder);
  await tester.tap(tabFinder);
  await tester.pumpAndSettle();
}

/// 挂载设置页并返回测试用数据库实例。
Future<AppDatabase> pumpSettingsScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1500),
  int initialTabIndex = 0,
  String? clipboardText = '',
  List<String>? clipboardWrites,
  List<dynamic> extraOverrides = const [],
}) async {
  await preferences.setInt(settingsLastTabIndexKey, initialTabIndex);

  // 设置空剪贴板，避免"新增"按钮的导入检测挂起平台通道
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments;
        final text = arguments is Map ? arguments['text'] : null;
        if (text is String) clipboardWrites?.add(text);
        return null;
      }
      if (call.method == 'Clipboard.hasStrings') {
        return <String, dynamic>{'value': false};
      }
      return null;
    },
  );

  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'presets/new',
            builder: (_, _) => const PresetEditorScreen(),
          ),
          GoRoute(
            path: 'presets/:presetId',
            builder: (_, state) =>
                PresetEditorScreen(presetId: state.pathParameters['presetId']),
          ),
          GoRoute(
            path: 'memory-prompts/new',
            builder: (_, _) => const MemoryPromptEditorScreen(),
          ),
          GoRoute(
            path: 'memory-prompts/:promptId',
            builder: (_, state) => MemoryPromptEditorScreen(
              promptId: state.pathParameters['promptId'],
            ),
          ),
          GoRoute(
            path: 'template-prompts/new',
            builder: (_, _) => const TemplatePromptEditorScreen(),
          ),
          GoRoute(
            path: 'template-prompts/:promptId',
            builder: (_, state) => TemplatePromptEditorScreen(
              promptId: state.pathParameters['promptId'],
            ),
          ),
          GoRoute(
            path: 'fixed-sequences/new',
            builder: (_, _) => const FixedPromptSequenceEditorScreen(),
          ),
          GoRoute(
            path: 'fixed-sequences/:sequenceId',
            builder: (_, state) => FixedPromptSequenceEditorScreen(
              sequenceId: state.pathParameters['sequenceId'],
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return pumpTestApp(
    tester,
    router: router,
    preferences: preferences,
    database: database,
    viewportSize: size,
    extraOverrides: [
      appNetworkLoggerProvider.overrideWithValue(const NoopNetworkLogger()),
      ...extraOverrides,
    ],
  );
}

Future<SharedPreferences> createEmptyPreferences(AppDatabase database) async {
  return TestFixtures.seedPreferences(database: database);
}

/// 标准设置页面测试环境：内存 DB、种子 Preferences、挂载 SettingsScreen。
/// [seed] 控制种子数据类型（null=空，defaults=含模型和提示词），
/// [size] 和 [initialTabIndex] 控制视口和初始标签页。
/// 返回 [AppDatabase] 供后续验证使用。
Future<AppDatabase> setUpSettingsScreen(
  WidgetTester tester, {
  Size size = const Size(1440, 1500),
  int initialTabIndex = 0,
  bool useDefaultsSeed = false,
  List<LlmModelConfig> models = const [],
  List<PresetPrompt> presetPrompts = const [],
  List<FixedPromptSequence> fixedPromptSequences = const [],
  List<MemoryPrompt> memoryPrompts = const [],
  List<TemplatePrompt> templatePrompts = const [],
  String? clipboardText = '',
  List<String>? clipboardWrites,
  List<dynamic> extraOverrides = const [],
}) async {
  assert(
    !useDefaultsSeed ||
        (models.isEmpty &&
            presetPrompts.isEmpty &&
            fixedPromptSequences.isEmpty &&
            memoryPrompts.isEmpty &&
            templatePrompts.isEmpty),
    'useDefaultsSeed 不能与显式种子同时使用',
  );
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = useDefaultsSeed
      ? await createDefaultsSeededPreferences(database)
      : await TestFixtures.seedPreferences(
          database: database,
          models: models,
          prompts: presetPrompts,
          sequences: fixedPromptSequences,
        );
  if (memoryPrompts.isNotEmpty) {
    await memoryPromptRepository.saveAll(database, memoryPrompts);
  }
  if (templatePrompts.isNotEmpty) {
    await templatePromptRepository.saveAll(database, templatePrompts);
  }
  await pumpSettingsScreen(
    tester,
    preferences: preferences,
    database: database,
    size: size,
    initialTabIndex: initialTabIndex,
    clipboardText: clipboardText,
    clipboardWrites: clipboardWrites,
    extraOverrides: extraOverrides,
  );
  return database;
}

/// 创建包含默认种子数据的 SharedPreferences 实例。
Future<SharedPreferences> createDefaultsSeededPreferences(
  AppDatabase database,
) async {
  return TestFixtures.seedPreferences(
    database: database,
    models: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
    prompts: [TestFixtures.presetPrompt(id: 'prompt-1', name: '代码助手')],
  );
}

// ── Finder 工厂 ────────────────────────────────────────────
//
// 以下 finder 按「dialog 类型 + 可见 label」定位输入控件，不再依赖源码中的
// ValueKey。label 在多个 dialog 重复时（如「标题」「名称」），由泛型参数
// 限定 dialog 祖先范围消除歧义；禁止全局「第 N 个 TextField」式定位。

/// 在指定 dialog 内按可见 label 定位输入框。
Finder fieldInDialog<T extends Widget>(String label) => find.descendant(
  of: find.byType(T),
  matching: find.widgetWithText(AppTextField, label),
);

Finder providerNameField() => fieldInDialog<ModelProviderFormDialog>('服务商名称');

/// 服务商对话框中的协议下拉框（DropdownButtonFormField 不是 TextFormField，
/// 需按泛型控件类型定位）。
Finder providerProtocolDropdown() => find.descendant(
  of: find.byType(ModelProviderFormDialog),
  matching: find.byType(DropdownButtonFormField<LlmApiProtocol>),
);

/// 在服务商对话框中把协议切换为 [protocol]（菜单项渲染在 Overlay 中，
/// 需等菜单开合动画结束）。
Future<void> selectProviderProtocol(
  WidgetTester tester,
  LlmApiProtocol protocol,
) async {
  await tester.tap(providerProtocolDropdown());
  await tester.pumpAndSettle();
  await tester.tap(find.text(protocol.displayName).last);
  await tester.pumpAndSettle();
}

Finder providerApiUrlField() =>
    fieldInDialog<ModelProviderFormDialog>('API URL');

Finder providerApiKeyField() =>
    fieldInDialog<ModelProviderFormDialog>('API Key');

Finder modelDisplayNameField() => fieldInDialog<ModelConfigFormDialog>('显示名称');

Finder modelApiNameField() => fieldInDialog<ModelConfigFormDialog>('API 模型名称');

/// 支持深度思考是 SwitchListTile 的整行标题，点击该文本即可切换开关。
Finder modelSupportsReasoningField() => find.descendant(
  of: find.byType(ModelConfigFormDialog),
  matching: find.text('支持深度思考'),
);

Finder presetPromptNameField() =>
    fieldInDialog<PresetPromptEditor>('预设 Prompt 名称');

Finder presetPromptTitleField() => fieldInDialog<PresetPromptEditor>('标题');

Finder presetPromptContentField() =>
    fieldInDialog<PresetPromptEditor>('Prompt 内容');

Finder fixedPromptSequenceNameField() =>
    fieldInDialog<FixedPromptSequenceEditor>('序列名称');

Finder fixedStepTitleField() =>
    fieldInDialog<FixedPromptSequenceEditor>('步骤标题');

Finder fixedStepContentField() =>
    fieldInDialog<FixedPromptSequenceEditor>('步骤内容');

Finder templatePromptTitleField() => fieldInDialog<TemplatePromptEditor>('标题');

Finder templatePromptContentField() =>
    fieldInDialog<TemplatePromptEditor>('模板提示词');

Finder templatePromptVariableField(String variableName) =>
    fieldInDialog<TemplatePromptEditor>(variableName);

Finder memoryPromptNameField() => fieldInDialog<MemoryPromptEditor>('名称');

Finder memoryPromptContentField() =>
    fieldInDialog<MemoryPromptEditor>('记忆总结提示词');

Future<void> createTestProvider(WidgetTester tester) async {
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
}
