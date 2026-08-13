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
import '../../domain/models/transfer/settings_export_codec.dart';
import '../../domain/models/prompts/template_prompt.dart';
import '../preferences/auto_retry_settings_controller.dart';
import '../preferences/custom_headers_controller.dart';
import '../prompts/fixed_prompt_sequences_controller.dart';
import '../preferences/font_size_settings_controller.dart';
import '../providers/llm_model_configs_controller.dart';
import '../prompts/memory_prompts_controller.dart';
import '../preferences/output_processing_settings_controller.dart';
import '../prompts/preset_prompts_controller.dart';
import 'settings_import_deduplicator.dart';
import '../prompts/template_prompts_controller.dart';

enum SettingsTransferTab {
  providers,
  presets,
  prompts,
  network,
  outputProcessing,
  other,
}

enum SettingsImportPreparationKind {
  invalidClipboard,
  unsupportedVersion,
  tabMismatch,
  noNewItems,
  ready,
}

final class SettingsImportPreparation {
  const SettingsImportPreparation(this.kind, {this.data});
  final SettingsImportPreparationKind kind;
  final SettingsExportData? data;
}

/// 设置页导入导出数据准备；不访问 Clipboard 或展示 UI。
final class SettingsTransferWorkflow {
  SettingsTransferWorkflow({
    List<LlmProviderConfig> Function()? readProviders,
    List<MemoryPrompt> Function()? readMemoryPrompts,
    List<PresetPrompt> Function()? readPresetPrompts,
    List<TemplatePrompt> Function()? readTemplatePrompts,
    List<FixedPromptSequence> Function()? readSequences,
    AutoRetrySettings Function()? readAutoRetry,
    CustomHeadersConfig Function()? readHeaders,
    FontSizeSettings Function()? readFontSize,
    OutputProcessingSettings Function()? readOutputProcessing,
    SettingsImportDeduplicator deduplicator =
        const SettingsImportDeduplicator(),
  }) : _readProviders = readProviders ?? _emptyProviders,
       _readMemoryPrompts = readMemoryPrompts ?? _emptyMemoryPrompts,
       _readPresetPrompts = readPresetPrompts ?? _emptyPresetPrompts,
       _readTemplatePrompts = readTemplatePrompts ?? _emptyTemplatePrompts,
       _readSequences = readSequences ?? _emptySequences,
       _readAutoRetry = readAutoRetry ?? _defaultAutoRetry,
       _readHeaders = readHeaders ?? _defaultHeaders,
       _readFontSize = readFontSize ?? _defaultFontSize,
       _readOutputProcessing = readOutputProcessing ?? _defaultOutputProcessing,
       _deduplicator = deduplicator;

  final List<LlmProviderConfig> Function() _readProviders;
  final List<MemoryPrompt> Function() _readMemoryPrompts;
  final List<PresetPrompt> Function() _readPresetPrompts;
  final List<TemplatePrompt> Function() _readTemplatePrompts;
  final List<FixedPromptSequence> Function() _readSequences;
  final AutoRetrySettings Function() _readAutoRetry;
  final CustomHeadersConfig Function() _readHeaders;
  final FontSizeSettings Function() _readFontSize;
  final OutputProcessingSettings Function() _readOutputProcessing;
  final SettingsImportDeduplicator _deduplicator;

  static List<LlmProviderConfig> _emptyProviders() => const [];
  static List<MemoryPrompt> _emptyMemoryPrompts() => const [];
  static List<PresetPrompt> _emptyPresetPrompts() => const [];
  static List<TemplatePrompt> _emptyTemplatePrompts() => const [];
  static List<FixedPromptSequence> _emptySequences() => const [];
  static AutoRetrySettings _defaultAutoRetry() => const AutoRetrySettings();
  static CustomHeadersConfig _defaultHeaders() => const CustomHeadersConfig();
  static FontSizeSettings _defaultFontSize() => const FontSizeSettings();
  static OutputProcessingSettings _defaultOutputProcessing() =>
      const OutputProcessingSettings();

  SettingsExportData? buildExportData(SettingsTransferTab tab) {
    final providers = _readProviders();
    final memory = _readMemoryPrompts();
    final presets = _readPresetPrompts();
    final templates = _readTemplatePrompts();
    final sequences = _readSequences();
    return switch (tab) {
      SettingsTransferTab.providers =>
        providers.isEmpty
            ? null
            : SettingsExportData(
                modelProviders: providers,
                memoryPrompts: const [],
                presetPrompts: const [],
                templatePrompts: const [],
                fixedPromptSequences: const [],
              ),
      SettingsTransferTab.presets =>
        presets.isEmpty
            ? null
            : SettingsExportData(
                modelProviders: const [],
                memoryPrompts: const [],
                presetPrompts: presets,
                templatePrompts: const [],
                fixedPromptSequences: const [],
              ),
      SettingsTransferTab.prompts =>
        memory.isEmpty && templates.isEmpty && sequences.isEmpty
            ? null
            : SettingsExportData(
                modelProviders: const [],
                memoryPrompts: memory,
                presetPrompts: const [],
                templatePrompts: templates,
                fixedPromptSequences: sequences,
              ),
      SettingsTransferTab.network =>
        _readHeaders().headers.isEmpty
            ? null
            : SettingsExportData(
                modelProviders: const [],
                memoryPrompts: const [],
                presetPrompts: const [],
                templatePrompts: const [],
                fixedPromptSequences: const [],
                customHeadersConfig: _readHeaders(),
              ),
      SettingsTransferTab.outputProcessing =>
        _readOutputProcessing().rules.isEmpty
            ? null
            : SettingsExportData(
                modelProviders: const [],
                memoryPrompts: const [],
                presetPrompts: const [],
                templatePrompts: const [],
                fixedPromptSequences: const [],
                outputProcessingSettings: _readOutputProcessing(),
              ),
      SettingsTransferTab.other => SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
        autoRetrySettings: _readAutoRetry(),
        fontSizeSettings: _readFontSize(),
      ),
    };
  }

  SettingsImportPreparation prepareImport({
    required SettingsTransferTab tab,
    required String? clipboardText,
  }) {
    final decode = SettingsExportCodec.decodeJson(clipboardText);
    if (decode is SettingsExportUnsupportedVersion) {
      return const SettingsImportPreparation(
        SettingsImportPreparationKind.unsupportedVersion,
      );
    }
    if (decode is! SettingsExportDecodeSuccess || !decode.data.hasContent) {
      return const SettingsImportPreparation(
        SettingsImportPreparationKind.invalidClipboard,
      );
    }
    final parsed = decode.data;
    if (!_matchesTab(parsed, tab)) {
      return const SettingsImportPreparation(
        SettingsImportPreparationKind.tabMismatch,
      );
    }
    final deduplicated = _deduplicator.deduplicate(
      data: parsed,
      existingProviders: _readProviders(),
      existingMemoryPrompts: _readMemoryPrompts(),
      existingPresetPrompts: _readPresetPrompts(),
      existingTemplatePrompts: _readTemplatePrompts(),
      existingSequences: _readSequences(),
      existingAutoRetrySettings: _readAutoRetry(),
      existingCustomHeadersConfig: _readHeaders(),
      existingFontSizeSettings: _readFontSize(),
      existingOutputProcessingSettings: _readOutputProcessing(),
    );
    if (!deduplicated.hasContent) {
      return const SettingsImportPreparation(
        SettingsImportPreparationKind.noNewItems,
      );
    }
    return SettingsImportPreparation(
      SettingsImportPreparationKind.ready,
      data: deduplicated,
    );
  }

  bool _matchesTab(SettingsExportData data, SettingsTransferTab tab) =>
      switch (tab) {
        SettingsTransferTab.providers => data.modelProviders.isNotEmpty,
        SettingsTransferTab.presets => data.presetPrompts.isNotEmpty,
        SettingsTransferTab.prompts =>
          data.memoryPrompts.isNotEmpty ||
              data.templatePrompts.isNotEmpty ||
              data.fixedPromptSequences.isNotEmpty,
        SettingsTransferTab.network =>
          data.customHeadersConfig?.headers.isNotEmpty ?? false,
        SettingsTransferTab.outputProcessing =>
          data.outputProcessingSettings?.rules.isNotEmpty ?? false,
        SettingsTransferTab.other =>
          data.autoRetrySettings != null || data.fontSizeSettings != null,
      };
}

final settingsTransferWorkflowProvider = Provider<SettingsTransferWorkflow>((
  ref,
) {
  return SettingsTransferWorkflow(
    readProviders: () => ref.read(llmProviderConfigsProvider),
    readMemoryPrompts: () => ref.read(memoryPromptsProvider),
    readPresetPrompts: () => ref.read(presetPromptsProvider),
    readTemplatePrompts: () => ref.read(templatePromptsProvider),
    readSequences: () => ref.read(fixedPromptSequencesProvider),
    readAutoRetry: () => ref.read(autoRetrySettingsProvider),
    readHeaders: () => ref.read(customHeadersProvider),
    readFontSize: () => ref.read(fontSizeSettingsProvider),
    readOutputProcessing: () => ref.read(outputProcessingSettingsProvider),
  );
});
