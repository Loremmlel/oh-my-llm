import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_import_executor.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

final class _RecordingTargets implements SettingsImportTargets {
  final calls = <String>[];
  Object? error;

  Future<void> _record(String name) async {
    calls.add(name);
    final failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<void> mergeImportedProviders(List<LlmProviderConfig> value) =>
      _record('providers');
  @override
  Future<void> saveAutoRetrySettings(AutoRetrySettings value) =>
      _record('retry');
  @override
  Future<void> saveCustomHeaders(CustomHeadersConfig value) =>
      _record('headers');
  @override
  Future<void> saveFontSize(FontSizeSettings value) => _record('font');
  @override
  Future<void> saveOutputProcessing(OutputProcessingSettings value) =>
      _record('output');
  @override
  Future<void> upsertFixedPromptSequences(List<FixedPromptSequence> value) =>
      _record('sequences');
  @override
  Future<void> upsertMemoryPrompts(List<MemoryPrompt> value) =>
      _record('memory');
  @override
  Future<void> upsertPresetPrompts(List<PresetPrompt> value) =>
      _record('presets');
  @override
  Future<void> upsertTemplatePrompts(List<TemplatePrompt> value) =>
      _record('templates');
}

SettingsExportData _fullData() => SettingsExportData(
  modelProviders: const [
    LlmProviderConfig(
      id: 'p',
      name: 'P',
      apiUrl: 'https://api.test',
      apiKey: 'key',
      apiProtocol: LlmApiProtocol.chatCompletions,
      models: [],
    ),
  ],
  memoryPrompts: [
    MemoryPrompt(
      id: 'm',
      name: 'M',
      content: 'content',
      updatedAt: DateTime(2026),
    ),
  ],
  presetPrompts: [
    PresetPrompt(
      id: 'pp',
      name: 'PP',
      messages: const [],
      updatedAt: DateTime(2026),
    ),
  ],
  templatePrompts: [
    TemplatePrompt(
      id: 'tp',
      title: 'TP',
      content: 'content',
      variables: const [],
      updatedAt: DateTime(2026),
    ),
  ],
  fixedPromptSequences: [
    FixedPromptSequence(
      id: 's',
      name: 'S',
      steps: const [],
      updatedAt: DateTime(2026),
    ),
  ],
  autoRetrySettings: const AutoRetrySettings(),
  customHeadersConfig: const CustomHeadersConfig(),
  fontSizeSettings: const FontSizeSettings(),
  outputProcessingSettings: const OutputProcessingSettings(),
);

void main() {
  group('SettingsImportExecutor', () {
    test('writes every non-empty category through typed targets', () async {
      final targets = _RecordingTargets();
      final executor = SettingsImportExecutor(targets: targets);

      expect(await executor.executeImport(data: _fullData()), isTrue);
      expect(targets.calls, [
        'providers',
        'memory',
        'presets',
        'templates',
        'sequences',
        'retry',
        'headers',
        'font',
        'output',
      ]);
    });

    test('returns false without calling a target for empty data', () async {
      final targets = _RecordingTargets();
      final executor = SettingsImportExecutor(targets: targets);
      const data = SettingsExportData(
        modelProviders: [],
        memoryPrompts: [],
        presetPrompts: [],
        templatePrompts: [],
        fixedPromptSequences: [],
      );

      expect(await executor.executeImport(data: data), isFalse);
      expect(targets.calls, isEmpty);
    });

    test('propagates target failure and stops later writes', () async {
      final targets = _RecordingTargets()..error = StateError('write failed');
      final executor = SettingsImportExecutor(targets: targets);

      await expectLater(
        executor.executeImport(data: _fullData()),
        throwsA(isA<StateError>()),
      );
      expect(targets.calls, ['providers']);
    });
  });
}
