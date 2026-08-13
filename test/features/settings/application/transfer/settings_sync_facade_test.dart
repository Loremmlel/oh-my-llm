import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/prompts/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;
  late ProviderContainer container;
  late SettingsSyncFacade facade;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    database = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsSyncFacadeProvider.overrideWith(
          (ref) => RiverpodSettingsSyncFacade(ref),
        ),
      ],
    );
    facade = container.read(settingsSyncFacadeProvider);
  });

  tearDown(() {
    container.dispose();
    database.close();
  });

  test('exportSelected 只导出选择的 providers 与 prompts', () async {
    final provider = LlmProviderConfig(
      id: 'provider-1',
      name: '测试服务商',
      apiUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      apiProtocol: LlmApiProtocol.chatCompletions,
      models: const [
        LlmProviderModelConfig(
          id: 'model-1',
          displayName: 'Test',
          modelName: 'test',
          supportsReasoning: false,
        ),
      ],
    );
    final memory = TestFixtures.memoryPrompt(id: 'memory-1');
    await container
        .read(llmProviderConfigsProvider.notifier)
        .upsertProvider(provider);
    await container.read(memoryPromptsProvider.notifier).upsert(memory);

    final data = facade.exportSelected(
      const SettingsSyncSelection(providers: true, prompts: true),
    );

    expect(data.modelProviders, [provider]);
    expect(data.memoryPrompts, [memory]);
    expect(data.presetPrompts, isEmpty);
    expect(data.autoRetrySettings, isNull);
  });

  test('deduplicateIncoming 过滤已有条目，importDeduplicated 写入新条目', () async {
    final existing = TestFixtures.memoryPrompt(
      id: 'memory-existing',
      content: '已有内容',
    );
    final incoming = TestFixtures.memoryPrompt(
      id: 'memory-new',
      content: '全新内容',
    );
    await container.read(memoryPromptsProvider.notifier).upsert(existing);
    final data = SettingsExportData(
      modelProviders: const [],
      memoryPrompts: [existing, incoming],
      presetPrompts: const [],
      templatePrompts: const [],
      fixedPromptSequences: const [],
    );

    final deduplicated = facade.deduplicateIncoming(data);
    expect(deduplicated.memoryPrompts, [incoming]);

    final imported = await facade.importDeduplicated(deduplicated);
    expect(imported, isTrue);
    expect(
      container.read(memoryPromptsProvider),
      containsAll([existing, incoming]),
    );
  });
}
