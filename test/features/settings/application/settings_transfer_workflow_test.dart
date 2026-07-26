import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/application/settings_transfer_workflow.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';

void main() {
  test('builds an export containing only the current providers tab data', () {
    final workflow = SettingsTransferWorkflow(
      readProviders: () => const [
        LlmProviderConfig(
          id: 'provider-1',
          name: 'OpenAI',
          apiUrl: 'https://api.test',
          apiKey: 'key',
          models: [],
        ),
      ],
    );

    final result = workflow.buildExportData(SettingsTransferTab.providers);

    expect(result, isNotNull);
    expect(result!.modelProviders, hasLength(1));
    expect(result.memoryPrompts, isEmpty);
    expect(result.presetPrompts, isEmpty);
  });

  test('reports tab mismatch before showing an import confirmation', () {
    final workflow = SettingsTransferWorkflow();
    final text = SettingsExportData(
      modelProviders: const [],
      memoryPrompts: const [],
      presetPrompts: [
        PresetPrompt(
          id: 'preset-1',
          name: '预设',
          messages: const [],
          updatedAt: DateTime(2026),
        ),
      ],
      templatePrompts: const [],
      fixedPromptSequences: const [],
    ).toJsonString();

    final result = workflow.prepareImport(
      tab: SettingsTransferTab.providers,
      clipboardText: text,
    );

    expect(result.kind, SettingsImportPreparationKind.tabMismatch);
  });
}
