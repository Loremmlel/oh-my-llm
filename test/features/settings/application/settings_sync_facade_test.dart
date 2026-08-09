import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_codec.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';

import '../../../helpers/fixtures.dart';

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

  // ── Sync snapshot 版本化 codec（复用导出格式，未改 wire 协议）─────────────

  group('Sync snapshot 版本化 codec', () {
    LlmProviderConfig syncProvider({required LlmApiProtocol apiProtocol}) {
      return LlmProviderConfig(
        id: 'provider-sync',
        name: 'Sync 服务商',
        apiUrl: 'https://api.example.com/v1',
        apiKey: 'sk-sync',
        apiProtocol: apiProtocol,
        models: const [
          LlmProviderModelConfig(
            id: 'model-sync',
            displayName: 'GPT-5',
            modelName: 'gpt-5',
            supportsReasoning: true,
          ),
        ],
      );
    }

    Map<String, Object?> snapshotOf(SettingsExportData data) {
      return SettingsExportCodec.encode(data);
    }

    test('协议字段 round-trip：encode 写出 apiProtocol，decode 原样还原', () {
      final data = SettingsExportData(
        modelProviders: [syncProvider(apiProtocol: LlmApiProtocol.responses)],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      );

      final snapshot = snapshotOf(data);
      expect(snapshot['formatVersion'], SettingsExportData.formatVersion);

      final decoded = SettingsExportCodec.decode(snapshot);
      expect(decoded, isA<SettingsExportDecodeSuccess>());
      final success = decoded as SettingsExportDecodeSuccess;
      expect(success.sourceVersion, SettingsExportData.formatVersion);
      expect(success.migrated, isFalse);
      expect(
        success.data.modelProviders.single.apiProtocol,
        LlmApiProtocol.responses,
      );
    });

    test('v6 快照可导入并补全 chatCompletions（迁移路径生效）', () {
      final v6 = {
        'identifier': SettingsExportData.identifier,
        'formatVersion': 6,
        'modelProviders': [
          {
            'id': 'provider-old',
            'name': '旧服务商',
            'apiUrl': 'https://old.example.com',
            'apiKey': 'sk-old',
            'models': <Object?>[],
          },
        ],
        'memoryPrompts': <Object?>[],
        'presetPrompts': <Object?>[],
        'templatePrompts': <Object?>[],
        'fixedPromptSequences': <Object?>[],
      };

      final decoded = SettingsExportCodec.decode(v6);
      expect(decoded, isA<SettingsExportDecodeSuccess>());
      final success = decoded as SettingsExportDecodeSuccess;
      expect(success.migrated, isTrue);
      expect(
        success.data.modelProviders.single.apiProtocol,
        LlmApiProtocol.chatCompletions,
      );
    });

    test('v5 快照经链式迁移同样可导入', () {
      final v5 = {
        'identifier': SettingsExportData.identifier,
        'version': 5,
        'modelProviders': [
          {
            'id': 'provider-old',
            'name': '旧服务商',
            'apiUrl': 'https://old.example.com',
            'apiKey': 'sk-old',
            'models': <Object?>[],
          },
        ],
        'memoryPrompts': <Object?>[],
        'presetPrompts': <Object?>[],
        'templatePrompts': <Object?>[],
        'fixedPromptSequences': <Object?>[],
      };

      final decoded = SettingsExportCodec.decode(v5);
      expect(decoded, isA<SettingsExportDecodeSuccess>());
      final success = decoded as SettingsExportDecodeSuccess;
      expect(success.migrated, isTrue);
      expect(
        success.data.modelProviders.single.apiProtocol,
        LlmApiProtocol.chatCompletions,
      );
    });

    test('未来版本快照与 malformed 输入被拒绝', () {
      final future = {
        'identifier': SettingsExportData.identifier,
        'formatVersion': 8,
        'modelProviders': <Object?>[],
      };
      expect(
        SettingsExportCodec.decode(future),
        isA<SettingsExportUnsupportedVersion>(),
      );
      expect(
        SettingsExportCodec.decodeJson('not a snapshot'),
        isA<SettingsExportMalformed>(),
      );
    });
  });
}
