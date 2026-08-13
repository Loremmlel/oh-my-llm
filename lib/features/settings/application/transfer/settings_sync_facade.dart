import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import '../../domain/models/transfer/settings_export_data.dart';
import '../preferences/auto_retry_settings_controller.dart';
import '../preferences/custom_headers_controller.dart';
import '../prompts/fixed_prompt_sequences_controller.dart';
import '../preferences/font_size_settings_controller.dart';
import '../providers/llm_model_configs_controller.dart';
import '../prompts/memory_prompts_controller.dart';
import '../preferences/output_processing_settings_controller.dart';
import '../prompts/preset_prompts_controller.dart';
import 'settings_import_deduplicator.dart';
import 'settings_import_executor.dart';
import '../prompts/template_prompts_controller.dart';

/// Settings application 对 Sync 暴露的聚合实现。
///
/// 读取、去重和写入全部留在 Settings 内，Sync 不再逐个读取 Settings controller。
final class RiverpodSettingsSyncFacade implements SettingsSyncFacade {
  const RiverpodSettingsSyncFacade(this._ref);

  final Ref _ref;

  @override
  SettingsExportData exportSelected(SettingsSyncSelection selection) {
    return SettingsExportData(
      modelProviders: selection.providers
          ? _ref.read(llmProviderConfigsProvider)
          : const [],
      presetPrompts: selection.presets
          ? _ref.read(presetPromptsProvider)
          : const [],
      memoryPrompts: selection.prompts
          ? _ref.read(memoryPromptsProvider)
          : const [],
      templatePrompts: selection.prompts
          ? _ref.read(templatePromptsProvider)
          : const [],
      fixedPromptSequences: selection.prompts
          ? _ref.read(fixedPromptSequencesProvider)
          : const [],
      autoRetrySettings: selection.other
          ? _ref.read(autoRetrySettingsProvider)
          : null,
      customHeadersConfig: selection.other
          ? _ref.read(customHeadersProvider)
          : null,
      fontSizeSettings: selection.other
          ? _ref.read(fontSizeSettingsProvider)
          : null,
      outputProcessingSettings: selection.other
          ? _ref.read(outputProcessingSettingsProvider)
          : null,
    );
  }

  @override
  SettingsExportData deduplicateIncoming(SettingsExportData data) {
    const deduplicator = SettingsImportDeduplicator();
    return deduplicator.deduplicate(
      data: data,
      existingProviders: _ref.read(llmProviderConfigsProvider),
      existingMemoryPrompts: _ref.read(memoryPromptsProvider),
      existingPresetPrompts: _ref.read(presetPromptsProvider),
      existingTemplatePrompts: _ref.read(templatePromptsProvider),
      existingSequences: _ref.read(fixedPromptSequencesProvider),
      existingAutoRetrySettings: _ref.read(autoRetrySettingsProvider),
      existingCustomHeadersConfig: _ref.read(customHeadersProvider),
      existingFontSizeSettings: _ref.read(fontSizeSettingsProvider),
      existingOutputProcessingSettings: _ref.read(
        outputProcessingSettingsProvider,
      ),
    );
  }

  @override
  Future<bool> importDeduplicated(SettingsExportData data) {
    return _ref.read(settingsImportExecutorProvider).executeImport(data: data);
  }
}
