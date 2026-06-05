import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/settings_import_executor.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

// ── 测试 harness ────────────────────────────────────────────────────────────

/// Riverpod 3.x 中 [ProviderContainer] 不再是 [Ref]，无法直接传给
/// [SettingsImportExecutor.executeImport]。此 Notifier 在 [build] 中
/// 捕获真实 Ref，并提供 [triggerImport] 方法把 SettingsExportData
/// 转交给 executor，返回是否写入了任何数据。
class _ExecutorHarness extends Notifier<bool> {
  late Ref _capturedRef;

  @override
  bool build() {
    _capturedRef = ref;
    return false;
  }

  Future<bool> triggerImport(SettingsExportData data) {
    return const SettingsImportExecutor().executeImport(_capturedRef, data: data);
  }
}

final _harnessProvider = NotifierProvider<_ExecutorHarness, bool>(_ExecutorHarness.new);

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider({String id = 'provider-1'}) {
  return LlmProviderConfig(
    id: id,
    name: 'OpenAI',
    apiUrl: 'https://api.openai.com/v1/chat/completions',
    apiKey: 'sk-test',
    models: const [],
  );
}

MemoryPrompt _memory({String id = 'mem-1'}) {
  return MemoryPrompt(
    id: id,
    name: '测试记忆',
    content: '请总结关键事实。',
    updatedAt: DateTime(2026, 1, 1),
  );
}

PresetPrompt _preset({String id = 'preset-1'}) {
  return PresetPrompt(
    id: id,
    name: '测试预设',
    messages: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

TemplatePrompt _template({String id = 'tpl-1'}) {
  return TemplatePrompt(
    id: id,
    title: '测试模板',
    content: '正文：{{body}}',
    variables: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

FixedPromptSequence _sequence({String id = 'seq-1'}) {
  return FixedPromptSequence(
    id: id,
    name: '测试序列',
    steps: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('SettingsImportExecutor', () {
    late SharedPreferences preferences;
    late AppDatabase database;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      database = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(() {
        container.dispose();
        database.close();
      });
    });

    test('写入 providers（走 mergeImportedProviders 路径）', () async {
      final harness = container.read(_harnessProvider.notifier);
      final data = SettingsExportData(
        modelProviders: [_provider()],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      );

      final wrote = await harness.triggerImport(data);

      expect(wrote, isTrue);
      final providers = container.read(llmProviderConfigsProvider);
      expect(providers.length, 1);
      expect(providers.first.id, 'provider-1');
    });

    test('写入 memoryPrompts / presetPrompts / templatePrompts / fixedPromptSequences',
        () async {
      final harness = container.read(_harnessProvider.notifier);
      final data = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: [_memory(id: 'm1'), _memory(id: 'm2')],
        presetPrompts: [_preset()],
        templatePrompts: [_template()],
        fixedPromptSequences: [_sequence()],
      );

      final wrote = await harness.triggerImport(data);

      expect(wrote, isTrue);
      expect(container.read(memoryPromptsProvider).length, 2);
      expect(container.read(presetPromptsProvider).length, 1);
      expect(container.read(templatePromptsProvider).length, 1);
      expect(container.read(fixedPromptSequencesProvider).length, 1);
      // providers 未被触碰
      expect(container.read(llmProviderConfigsProvider), isEmpty);
    });

    test('写入 autoRetrySettings（走 save 路径）', () async {
      final harness = container.read(_harnessProvider.notifier);
      final data = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
        autoRetrySettings: const AutoRetrySettings(
          maxJitterSeconds: 20,
          maxRetryCount: 5,
        ),
      );

      final wrote = await harness.triggerImport(data);

      expect(wrote, isTrue);
      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 20);
      expect(settings.maxRetryCount, 5);
    });

    test('全空时返回 false，各 controller 保持空', () async {
      final harness = container.read(_harnessProvider.notifier);
      const data = SettingsExportData(
        modelProviders: [],
        memoryPrompts: [],
        presetPrompts: [],
        templatePrompts: [],
        fixedPromptSequences: [],
      );

      final wrote = await harness.triggerImport(data);

      expect(wrote, isFalse);
      expect(container.read(llmProviderConfigsProvider), isEmpty);
      expect(container.read(memoryPromptsProvider), isEmpty);
      expect(container.read(presetPromptsProvider), isEmpty);
      expect(container.read(templatePromptsProvider), isEmpty);
      expect(container.read(fixedPromptSequencesProvider), isEmpty);
    });
  });
}
