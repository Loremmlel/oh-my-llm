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
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider({
  String id = 'provider-1',
  String name = 'OpenAI',
  String apiUrl = 'https://api.openai.com/v1/chat/completions',
  String apiKey = 'sk-test',
}) {
  return LlmProviderConfig(
    id: id,
    name: name,
    apiUrl: apiUrl,
    apiKey: apiKey,
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

const AutoRetrySettings _autoRetry = AutoRetrySettings(
  maxJitterSeconds: 20,
  maxRetryCount: 5,
);

SettingsExportData _buildFullData() {
  return SettingsExportData(
    modelProviders: [_provider()],
    memoryPrompts: [_memory()],
    presetPrompts: [_preset()],
    templatePrompts: [_template()],
    fixedPromptSequences: [_sequence()],
    autoRetrySettings: _autoRetry,
  );
}

/// 测试用子类：覆盖 build() 以注入预设 state，绕开 Notifier 的受保护 state 写入。
///
/// 这样我们可以在不发起真实 requestSync 的前提下，把 controller 推进到 received 阶段，
/// 专门验证 executeImport() 的写入行为。
class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this._seed);

  final SyncClientState _seed;

  @override
  SyncClientState build() => _seed;
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('SyncClientController.executeImport', () {
    late SharedPreferences preferences;
    late AppDatabase database;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      database = AppDatabase.inMemory();
    });

    ProviderContainer buildContainer({SyncClientState? seed}) {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
          if (seed != null)
            syncClientControllerProvider.overrideWith(
              () => _SeededSyncClientController(seed),
            ),
        ],
      );
      addTearDown(() {
        container.dispose();
        database.close();
      });
      return container;
    }

    test('在 deduplicatedData 为 null 时返回 false，phase 不变', () async {
      final container = buildContainer();

      final result = await container
          .read(syncClientControllerProvider.notifier)
          .executeImport();

      expect(result, isFalse);
      expect(
        container.read(syncClientControllerProvider).phase,
        SyncPhase.idle,
      );
      expect(container.read(llmProviderConfigsProvider), isEmpty);
      expect(container.read(memoryPromptsProvider), isEmpty);
    });

    test('在 deduplicatedData 非空时写入全部六类数据并推进到 done', () async {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.received,
          deduplicatedData: _buildFullData(),
          sourceDeviceName: 'Test-PC',
        ),
      );

      final result = await container
          .read(syncClientControllerProvider.notifier)
          .executeImport();

      expect(result, isTrue);
      expect(
        container.read(syncClientControllerProvider).phase,
        SyncPhase.done,
      );

      // 服务商
      final providers = container.read(llmProviderConfigsProvider);
      expect(providers.length, 1);
      expect(providers.first.id, 'provider-1');

      // 四类提示词
      expect(container.read(memoryPromptsProvider).length, 1);
      expect(container.read(memoryPromptsProvider).first.id, 'mem-1');
      expect(container.read(presetPromptsProvider).length, 1);
      expect(container.read(templatePromptsProvider).length, 1);
      expect(container.read(fixedPromptSequencesProvider).length, 1);

      // 自动重试设置
      final autoRetry = container.read(autoRetrySettingsProvider);
      expect(autoRetry.maxJitterSeconds, 20);
      expect(autoRetry.maxRetryCount, 5);
    });

    test('仅写入非空分类，空分类不触发对应 controller 写入', () async {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.received,
          deduplicatedData: SettingsExportData(
            modelProviders: const [],
            memoryPrompts: const [],
            presetPrompts: const [],
            templatePrompts: const [],
            fixedPromptSequences: const [],
            autoRetrySettings: _autoRetry,
          ),
        ),
      );

      final result = await container
          .read(syncClientControllerProvider.notifier)
          .executeImport();

      expect(result, isTrue);
      expect(container.read(llmProviderConfigsProvider), isEmpty);
      expect(container.read(memoryPromptsProvider), isEmpty);
      expect(container.read(presetPromptsProvider), isEmpty);
      expect(container.read(templatePromptsProvider), isEmpty);
      expect(container.read(fixedPromptSequencesProvider), isEmpty);

      // 仅 autoRetrySettings 被写入。
      final autoRetry = container.read(autoRetrySettingsProvider);
      expect(autoRetry.maxRetryCount, 5);
    });
  });
}
