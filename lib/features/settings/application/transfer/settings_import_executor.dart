import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/preferences/auto_retry_settings.dart';
import '../../domain/models/preferences/custom_headers_config.dart';
import '../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../domain/models/preferences/font_size_settings.dart';
import '../../domain/models/providers/llm_provider_config.dart';
import '../../domain/models/prompts/memory_prompt.dart';
import '../../domain/models/preferences/output_processing_settings.dart';
import '../../domain/models/prompts/preset_prompt.dart';
import '../../domain/models/transfer/settings_export_data.dart';
import '../../domain/models/prompts/template_prompt.dart';
import '../preferences/auto_retry_settings_controller.dart';
import '../preferences/custom_headers_controller.dart';
import '../prompts/fixed_prompt_sequences_controller.dart';
import '../preferences/font_size_settings_controller.dart';
import '../providers/llm_model_configs_controller.dart';
import '../prompts/memory_prompts_controller.dart';
import '../preferences/output_processing_settings_controller.dart';
import '../prompts/preset_prompts_controller.dart';
import '../prompts/template_prompts_controller.dart';

/// 设置导入所需的类型化写入目标。
abstract interface class SettingsImportTargets {
  Future<void> mergeImportedProviders(List<LlmProviderConfig> value);
  Future<void> upsertMemoryPrompts(List<MemoryPrompt> value);
  Future<void> upsertPresetPrompts(List<PresetPrompt> value);
  Future<void> upsertTemplatePrompts(List<TemplatePrompt> value);
  Future<void> upsertFixedPromptSequences(List<FixedPromptSequence> value);
  Future<void> saveAutoRetrySettings(AutoRetrySettings value);
  Future<void> saveCustomHeaders(CustomHeadersConfig value);
  Future<void> saveFontSize(FontSizeSettings value);
  Future<void> saveOutputProcessing(OutputProcessingSettings value);
}

/// 设置导入的统一写入执行器。
final class SettingsImportExecutor {
  const SettingsImportExecutor({required this.targets});

  final SettingsImportTargets targets;

  /// 每个非空分类完成真实提交后才继续下一个分类。
  Future<bool> executeImport({required SettingsExportData data}) async {
    var wrote = false;
    if (data.modelProviders.isNotEmpty) {
      await targets.mergeImportedProviders(data.modelProviders);
      wrote = true;
    }
    if (data.memoryPrompts.isNotEmpty) {
      await targets.upsertMemoryPrompts(data.memoryPrompts);
      wrote = true;
    }
    if (data.presetPrompts.isNotEmpty) {
      await targets.upsertPresetPrompts(data.presetPrompts);
      wrote = true;
    }
    if (data.templatePrompts.isNotEmpty) {
      await targets.upsertTemplatePrompts(data.templatePrompts);
      wrote = true;
    }
    if (data.fixedPromptSequences.isNotEmpty) {
      await targets.upsertFixedPromptSequences(data.fixedPromptSequences);
      wrote = true;
    }
    final retry = data.autoRetrySettings;
    if (retry != null) {
      await targets.saveAutoRetrySettings(retry);
      wrote = true;
    }
    final headers = data.customHeadersConfig;
    if (headers != null) {
      await targets.saveCustomHeaders(headers);
      wrote = true;
    }
    final fontSize = data.fontSizeSettings;
    if (fontSize != null) {
      await targets.saveFontSize(fontSize);
      wrote = true;
    }
    final outputProcessing = data.outputProcessingSettings;
    if (outputProcessing != null) {
      await targets.saveOutputProcessing(outputProcessing);
      wrote = true;
    }
    return wrote;
  }
}

final settingsImportExecutorProvider = Provider<SettingsImportExecutor>((ref) {
  return SettingsImportExecutor(targets: _RiverpodSettingsImportTargets(ref));
});

final class _RiverpodSettingsImportTargets implements SettingsImportTargets {
  const _RiverpodSettingsImportTargets(this._ref);

  final Ref _ref;

  @override
  Future<void> mergeImportedProviders(List<LlmProviderConfig> value) => _ref
      .read(llmProviderConfigsProvider.notifier)
      .mergeImportedProviders(value);
  @override
  Future<void> saveAutoRetrySettings(AutoRetrySettings value) =>
      _ref.read(autoRetrySettingsProvider.notifier).save(value);
  @override
  Future<void> saveCustomHeaders(CustomHeadersConfig value) =>
      _ref.read(customHeadersProvider.notifier).save(value);
  @override
  Future<void> saveFontSize(FontSizeSettings value) =>
      _ref.read(fontSizeSettingsProvider.notifier).save(value);
  @override
  Future<void> saveOutputProcessing(OutputProcessingSettings value) =>
      _ref.read(outputProcessingSettingsProvider.notifier).save(value);
  @override
  Future<void> upsertFixedPromptSequences(List<FixedPromptSequence> value) =>
      _ref.read(fixedPromptSequencesProvider.notifier).upsertAll(value);
  @override
  Future<void> upsertMemoryPrompts(List<MemoryPrompt> value) =>
      _ref.read(memoryPromptsProvider.notifier).upsertAll(value);
  @override
  Future<void> upsertPresetPrompts(List<PresetPrompt> value) =>
      _ref.read(presetPromptsProvider.notifier).upsertAll(value);
  @override
  Future<void> upsertTemplatePrompts(List<TemplatePrompt> value) =>
      _ref.read(templatePromptsProvider.notifier).upsertAll(value);
}
