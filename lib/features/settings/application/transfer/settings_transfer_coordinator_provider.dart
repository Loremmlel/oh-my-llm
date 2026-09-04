import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/preferences/auto_retry_settings.dart';
import '../../domain/models/preferences/custom_headers_config.dart';
import '../../domain/models/preferences/font_size_settings.dart';
import '../../domain/models/preferences/output_processing_settings.dart';
import '../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../domain/models/prompts/memory_prompt.dart';
import '../../domain/models/prompts/preset_prompt.dart';
import '../../domain/models/prompts/template_prompt.dart';
import '../../domain/models/providers/llm_provider_config.dart';
import '../../domain/template_prompt_language/template_prompt_compiler.dart';
import '../preferences/auto_retry_settings_controller.dart';
import '../preferences/custom_headers_controller.dart';
import '../preferences/font_size_settings_controller.dart';
import '../preferences/output_processing_settings_controller.dart';
import '../prompts/fixed_prompt_sequences_controller.dart';
import '../prompts/memory_prompts_controller.dart';
import '../prompts/preset_prompts_controller.dart';
import '../prompts/template_prompts_controller.dart';
import '../providers/llm_model_configs_controller.dart';
import '../providers/llm_provider_import_merger.dart';
import 'settings_transfer_coordinator.dart';
import 'settings_transfer_payload.dart';
import 'settings_transfer_section.dart';
import 'settings_transfer_types.dart';

final settingsTransferCoordinatorProvider =
    Provider<SettingsTransferCoordinator>(
      (ref) => SettingsTransferCoordinator(sections: _fixedSections(ref)),
    );

List<SettingsTransferSection> _fixedSections(Ref ref) => [
  SettingsTransferSection.custom<List<LlmProviderConfig>>(
    key: 'modelProviders',
    group: SettingsTransferGroup.providers,
    label: '服务商',
    order: 0,
    sensitivity: SettingsTransferSensitivity.credentialBearing,
    readLocal: () => ref.read(llmProviderConfigsProvider),
    write: (value) => ref
        .read(llmProviderConfigsProvider.notifier)
        .replaceAllAfterImport(value),
    shouldExport: (value) => value.isNotEmpty,
    encode: _encodeProviders,
    decode: _decodeProviders,
    prepareImport: (local, incoming) {
      final merged = mergeImportedLlmProviders(
        local: local,
        incoming: incoming,
      );
      final normalizedLocal = mergeImportedLlmProviders(
        local: local,
        incoming: const [],
      );
      if (_sameProviders(normalizedLocal, merged)) return null;
      final writeValue = List<LlmProviderConfig>.unmodifiable(merged);
      return SettingsTransferChange<List<LlmProviderConfig>>(
        incoming: List<LlmProviderConfig>.unmodifiable(incoming),
        writeValue: writeValue,
        fingerprint: jsonEncode(_encodeProviders(writeValue)),
        summary: SettingsTransferSummaryItem(
          key: 'modelProviders',
          label: '服务商',
          action: SettingsTransferSummaryAction.add,
          count: incoming.length,
        ),
      );
    },
    summarizeExport: (value) => SettingsTransferSummaryItem(
      key: 'modelProviders',
      label: '服务商',
      action: SettingsTransferSummaryAction.add,
      count: value.length,
    ),
  ),
  SettingsTransferSection.merging<PresetPrompt>(
    key: 'presetPrompts',
    group: SettingsTransferGroup.presets,
    label: '预设提示词',
    order: 0,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(presetPromptsProvider),
    write: (value) => ref.read(presetPromptsProvider.notifier).upsertAll(value),
    encodeItem: (value) => value.toJson(),
    decodeItem: PresetPrompt.fromJson,
    isEquivalent: _samePresetPrompt,
  ),
  SettingsTransferSection.merging<MemoryPrompt>(
    key: 'memoryPrompts',
    group: SettingsTransferGroup.prompts,
    label: '记忆提示词',
    order: 0,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(memoryPromptsProvider),
    write: (value) => ref.read(memoryPromptsProvider.notifier).upsertAll(value),
    encodeItem: (value) => value.toJson(),
    decodeItem: MemoryPrompt.fromJson,
    isEquivalent: (existing, incoming) => existing.content == incoming.content,
  ),
  SettingsTransferSection.merging<TemplatePrompt>(
    key: 'templatePrompts',
    group: SettingsTransferGroup.prompts,
    label: '模板提示词',
    order: 1,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(templatePromptsProvider),
    write: (value) =>
        ref.read(templatePromptsProvider.notifier).upsertAll(value),
    encodeItem: (value) => value.toJson(),
    decodeItem: TemplatePrompt.fromJson,
    isEquivalent: _sameTemplatePrompt,
    validateItem: _validateTemplatePrompt,
  ),
  SettingsTransferSection.merging<FixedPromptSequence>(
    key: 'fixedPromptSequences',
    group: SettingsTransferGroup.prompts,
    label: '固定提示词序列',
    order: 2,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(fixedPromptSequencesProvider),
    write: (value) =>
        ref.read(fixedPromptSequencesProvider.notifier).upsertAll(value),
    encodeItem: (value) => value.toJson(),
    decodeItem: FixedPromptSequence.fromJson,
    isEquivalent: _sameFixedPromptSequence,
  ),
  SettingsTransferSection.replacing<CustomHeadersConfig>(
    key: 'customHeaders',
    group: SettingsTransferGroup.network,
    label: '自定义请求头',
    order: 0,
    sensitivity: SettingsTransferSensitivity.credentialBearing,
    readLocal: () => ref.read(customHeadersProvider),
    write: (value) => ref.read(customHeadersProvider.notifier).save(value),
    encode: (value) => value.toJson(),
    decode: CustomHeadersConfig.fromJson,
    isEmpty: (value) => value.headers.isEmpty,
  ),
  SettingsTransferSection.replacing<OutputProcessingSettings>(
    key: 'outputProcessing',
    group: SettingsTransferGroup.outputProcessing,
    label: '输出处理',
    order: 0,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(outputProcessingSettingsProvider),
    write: (value) =>
        ref.read(outputProcessingSettingsProvider.notifier).save(value),
    encode: (value) => value.toJson(),
    decode: OutputProcessingSettings.fromJson,
    isEmpty: (value) => value.rules.isEmpty,
  ),
  SettingsTransferSection.replacing<FontSizeSettings>(
    key: 'fontSizeSettings',
    group: SettingsTransferGroup.other,
    label: '正文字号设置',
    order: 0,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(fontSizeSettingsProvider),
    write: (value) => ref.read(fontSizeSettingsProvider.notifier).save(value),
    encode: (value) => value.toJson(),
    decode: FontSizeSettings.fromJson,
  ),
  SettingsTransferSection.replacing<AutoRetrySettings>(
    key: 'autoRetrySettings',
    group: SettingsTransferGroup.other,
    label: '自动重试设置',
    order: 1,
    sensitivity: SettingsTransferSensitivity.standard,
    readLocal: () => ref.read(autoRetrySettingsProvider),
    write: (value) => ref.read(autoRetrySettingsProvider.notifier).save(value),
    encode: (value) => value.toJson(),
    decode: AutoRetrySettings.fromJson,
  ),
];

Object _encodeProviders(List<LlmProviderConfig> value) =>
    value.map((provider) => provider.toJson()).toList(growable: false);

List<LlmProviderConfig> _decodeProviders(Object? payload) {
  return decodeTransferObjectList(payload, '服务商')
      .map((item) {
        if (item['apiProtocol'] == null) {
          throw const FormatException('服务商缺少有效 apiProtocol');
        }
        return LlmProviderConfig.fromJson(item);
      })
      .toList(growable: false);
}

bool _sameProviders(
  List<LlmProviderConfig> left,
  List<LlmProviderConfig> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _samePresetPrompt(PresetPrompt existing, PresetPrompt incoming) {
  if (existing.messages.length != incoming.messages.length) return false;
  for (var index = 0; index < existing.messages.length; index += 1) {
    final left = existing.messages[index];
    final right = incoming.messages[index];
    if (left.title != right.title ||
        left.role != right.role ||
        left.placement != right.placement ||
        left.content != right.content) {
      return false;
    }
  }
  return true;
}

bool _sameTemplatePrompt(TemplatePrompt existing, TemplatePrompt incoming) {
  if (existing.content != incoming.content ||
      existing.variables.length != incoming.variables.length) {
    return false;
  }
  for (var index = 0; index < existing.variables.length; index += 1) {
    if (existing.variables[index] != incoming.variables[index]) return false;
  }
  return true;
}

void _validateTemplatePrompt(TemplatePrompt template) {
  final compilation = compileTemplatePromptDefinition(template);
  if (!compilation.isValid) {
    throw FormatException('模板「${template.title}」定义无效');
  }
}

bool _sameFixedPromptSequence(
  FixedPromptSequence existing,
  FixedPromptSequence incoming,
) {
  if (existing.steps.length != incoming.steps.length) return false;
  for (var index = 0; index < existing.steps.length; index += 1) {
    final left = existing.steps[index];
    final right = incoming.steps[index];
    if (left.title != right.title || left.content != right.content) {
      return false;
    }
  }
  return true;
}
