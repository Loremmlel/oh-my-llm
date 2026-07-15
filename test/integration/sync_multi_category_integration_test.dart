/// Sync 多品类端到端集成测试。
///
/// 验证 presets/prompts/other 三个品类的完整同步链路：
/// 服务端种子数据 -> HTTP 服务 -> 客户端请求 -> 去重 -> 导入 -> 控制器状态验证。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider() => const LlmProviderConfig(
      id: 'pvd-1',
      name: 'TestProvider',
      apiUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test-key',
      models: [
        LlmProviderModelConfig(
          id: 'model-1',
          displayName: 'TestModel',
          modelName: 'test-model',
          supportsReasoning: false,
        ),
      ],
    );

/// 测试用子类：注入预设 state。
class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this._seed);
  final SyncClientState _seed;
  @override
  SyncClientState build() => _seed;
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  late SharedPreferences prefs;
  late AppDatabase serverDb;
  late AppDatabase clientDb;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    serverDb = AppDatabase.inMemory();
    clientDb = AppDatabase.inMemory();
    // 注意：SharedPreferences 在测试中是单例，server 和 client 共享同一实例。
    // SQLite 数据通过独立的 serverDb/clientDb 隔离。
  });

  tearDown(() {
    serverDb.close();
    clientDb.close();
  });

  ProviderContainer buildServerContainer() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(serverDb),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  ProviderContainer buildClientContainer({SyncClientState? seed}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(clientDb),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (seed != null)
          syncClientControllerProvider.overrideWith(
            () => _SeededSyncClientController(seed),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // ── presets 品类端到端 ──────────────────────────────────────────────────────

  test('presets 品类 -> 客户端导入后 presetPromptsProvider 有数据', () async {
    serverDb.connection.execute(
      "INSERT INTO preset_prompts (id, name, messages_json, updated_at) "
      "VALUES ('preset-1', '测试预设', '[]', '2026-07-01T00:00:00.000')",
    );

    final serverContainer = buildServerContainer();
    await serverContainer.read(syncServerControllerProvider.notifier).start();
    final httpPort = serverContainer.read(syncServerControllerProvider).httpPort!;

    final clientContainer = buildClientContainer(
      seed: SyncClientState(
        phase: SyncPhase.connected,
        server: DiscoveredServer(
          deviceName: 'ServerPC',
          ip: '127.0.0.1',
          httpPort: httpPort,
        ),
        selectedCategories: {SyncCategory.presets},
      ),
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .requestSync();

    expect(
      clientContainer.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );

    final imported = await clientContainer
        .read(syncClientControllerProvider.notifier)
        .executeImport();
    expect(imported, isTrue);

    final presets = clientContainer.read(presetPromptsProvider);
    expect(presets, hasLength(1));
    expect(presets.first.id, 'preset-1');
    expect(presets.first.name, '测试预设');
  });

  // ── prompts 品类端到端 ──────────────────────────────────────────────────────

  test('prompts 品类 -> 客户端导入后记忆/模板/固定序列均有数据', () async {
    serverDb.connection.execute(
      "INSERT INTO memory_prompts (id, name, content, updated_at) "
      "VALUES ('memory-1', '测试记忆', '关键约束信息', '2026-07-01T00:00:00.000')",
    );
    serverDb.connection.execute(
      "INSERT INTO template_prompts (id, title, content, variables_json, updated_at) "
      "VALUES ('template-1', '测试模板', '请处理{{正文}}', '[]', '2026-07-01T00:00:00.000')",
    );
    serverDb.connection.execute(
      "INSERT INTO fixed_prompt_sequences (id, name, steps_json, updated_at) "
      "VALUES ('sequence-1', '测试序列', "
      "'[{\"id\":\"step-1\",\"content\":\"步骤一\",\"title\":\"\"}]', "
      "'2026-07-01T00:00:00.000')",
    );

    final serverContainer = buildServerContainer();
    await serverContainer.read(syncServerControllerProvider.notifier).start();
    final httpPort = serverContainer.read(syncServerControllerProvider).httpPort!;

    final clientContainer = buildClientContainer(
      seed: SyncClientState(
        phase: SyncPhase.connected,
        server: DiscoveredServer(
          deviceName: 'ServerPC',
          ip: '127.0.0.1',
          httpPort: httpPort,
        ),
        selectedCategories: {SyncCategory.prompts},
      ),
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .requestSync();

    expect(
      clientContainer.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .executeImport();

    expect(clientContainer.read(memoryPromptsProvider), hasLength(1));
    expect(clientContainer.read(templatePromptsProvider), hasLength(1));
    expect(clientContainer.read(fixedPromptSequencesProvider), hasLength(1));

    expect(clientContainer.read(memoryPromptsProvider).first.id, 'memory-1');
    expect(clientContainer.read(templatePromptsProvider).first.id, 'template-1');
    expect(clientContainer.read(fixedPromptSequencesProvider).first.id, 'sequence-1');
  });

  // ── other 品类端到端 ────────────────────────────────────────────────────────

  test('other 品类 -> 两端配置一致时同步识别为无新数据', () async {
    // SharedPreferences 是单例，服务端写入后客户端也能读到
    await prefs.setString(
      'settings.auto_retry',
      jsonEncode({
        'maxJitterSeconds': 10,
        'maxRetryCount': 5,
        'retryMode': 'fixedInterval',
      }),
    );
    await prefs.setString(
      'settings.custom_headers',
      jsonEncode({
        'headers': [
          {'key': 'X-Custom-Header', 'value': 'test-value'}
        ],
      }),
    );

    final serverContainer = buildServerContainer();
    await serverContainer.read(syncServerControllerProvider.notifier).start();
    final httpPort = serverContainer.read(syncServerControllerProvider).httpPort!;

    // 由于 SharedPreferences 是单例，客户端与服务端读到相同配置。
    // 去重后应识别为"两端一致，无新数据"。
    final clientContainer = buildClientContainer(
      seed: SyncClientState(
        phase: SyncPhase.connected,
        server: DiscoveredServer(
          deviceName: 'ServerPC',
          ip: '127.0.0.1',
          httpPort: httpPort,
        ),
        selectedCategories: {SyncCategory.other},
      ),
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .requestSync();

    expect(
      clientContainer.read(syncClientControllerProvider).phase,
      SyncPhase.noNewData,
    );
  });

  // ── 多品类同时同步 ──────────────────────────────────────────────────────────

  test('多品类同时同步 -> 全部导入成功', () async {
    await prefs.setString(
      'settings.llm_model_configs',
      VersionedJsonStorage.encodeObjectList(
        items: [_provider()],
        toJson: (p) => p.toJson(),
      ),
    );
    await prefs.setString(
      'settings.auto_retry',
      jsonEncode({
        'maxJitterSeconds': 10,
        'maxRetryCount': 5,
        'retryMode': 'fixedInterval',
      }),
    );
    serverDb.connection.execute(
      "INSERT INTO preset_prompts (id, name, messages_json, updated_at) "
      "VALUES ('preset-1', '测试预设', '[]', '2026-07-01T00:00:00.000')",
    );
    serverDb.connection.execute(
      "INSERT INTO memory_prompts (id, name, content, updated_at) "
      "VALUES ('memory-1', '测试记忆', '内容', '2026-07-01T00:00:00.000')",
    );

    final serverContainer = buildServerContainer();
    await serverContainer.read(syncServerControllerProvider.notifier).start();
    final httpPort = serverContainer.read(syncServerControllerProvider).httpPort!;

    final clientContainer = buildClientContainer(
      seed: SyncClientState(
        phase: SyncPhase.connected,
        server: DiscoveredServer(
          deviceName: 'ServerPC',
          ip: '127.0.0.1',
          httpPort: httpPort,
        ),
        selectedCategories: {
          SyncCategory.providers,
          SyncCategory.presets,
          SyncCategory.prompts,
          SyncCategory.other,
        },
      ),
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .requestSync();

    expect(
      clientContainer.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );

    await clientContainer
        .read(syncClientControllerProvider.notifier)
        .executeImport();

    expect(clientContainer.read(llmProviderConfigsProvider), isNotEmpty);
    expect(clientContainer.read(presetPromptsProvider), hasLength(1));
    expect(clientContainer.read(memoryPromptsProvider), hasLength(1));
    expect(clientContainer.read(autoRetrySettingsProvider).maxRetryCount, 5);
  });
}
