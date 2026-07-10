import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';

import 'sync_screen_test_helpers.dart';

void registerSyncScreenImportDialogTests() {
  group('SyncImportConfirmDialog', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    SettingsExportData buildTestData() {
      return SettingsExportData(
        modelProviders: [
          LlmProviderConfig(
            id: 'pvd-1',
            name: 'OpenAI',
            apiUrl: 'https://api.openai.com/v1',
            apiKey: 'sk-test',
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'GPT-4',
                modelName: 'gpt-4',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        memoryPrompts: [
          MemoryPrompt(
            id: 'mem-1',
            name: '测试记忆',
            content: '请总结关键事实',
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      );
    }

    testWidgets('显示来源设备名和各分类数量', (tester) async {
      await pumpImportDialog(
        tester,
        preferences: preferences,
        exportData: buildTestData(),
      );

      expect(find.text('确认同步配置'), findsOneWidget);
      expect(find.textContaining('TestPC'), findsOneWidget);
      expect(find.text('LLM 服务商'), findsOneWidget);
      expect(find.text('记忆总结提示词'), findsOneWidget);
    });

    testWidgets('取消按钮关闭对话框', (tester) async {
      await pumpImportDialog(
        tester,
        preferences: preferences,
        exportData: const SettingsExportData(
          modelProviders: [],
          memoryPrompts: [],
          presetPrompts: [],
          templatePrompts: [],
          fixedPromptSequences: [],
        ),
      );
      expect(find.text('确认同步配置'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('确认同步配置'), findsNothing);
    });
  });
}
