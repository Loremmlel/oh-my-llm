import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider({
  String id = 'pvd-1',
  String apiUrl = 'https://api.example.com/v1',
  String apiKey = 'sk-test-key',
}) {
  return LlmProviderConfig(
    id: id,
    name: 'TestProvider',
    apiUrl: apiUrl,
    apiKey: apiKey,
    models: [
      LlmProviderModelConfig(
        id: 'model-1',
        displayName: 'TestModel',
        modelName: 'test-model',
        supportsReasoning: false,
      ),
    ],
  );
}

/// 测试用子类：注入预设 state（server + categories）。
class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this._seed);

  final SyncClientState _seed;

  @override
  SyncClientState build() => _seed;
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('Sync E2E 集成测试', () {
    late SharedPreferences serverPrefs;
    late SharedPreferences clientPrefs;
    late AppDatabase serverDb;
    late AppDatabase clientDb;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      serverPrefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues({});
      clientPrefs = await SharedPreferences.getInstance();
      serverDb = AppDatabase.inMemory();
      clientDb = AppDatabase.inMemory();
    });

    tearDown(() {
      serverDb.close();
      clientDb.close();
    });

    ProviderContainer buildServerContainer() {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(serverDb),
          sharedPreferencesProvider.overrideWithValue(serverPrefs),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    ProviderContainer buildClientContainer({SyncClientState? seed}) {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(clientDb),
          sharedPreferencesProvider.overrideWithValue(clientPrefs),
          if (seed != null)
            syncClientControllerProvider.overrideWith(
              () => _SeededSyncClientController(seed),
            ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('服务端有 provider → 客户端请求 → phase=received → 导入成功', () async {
      // ── 服务端种子 ──
      final provider = _provider();
      await serverPrefs.setString(
        'settings.llm_model_configs',
        VersionedJsonStorage.encodeObjectList(
          items: [provider],
          toJson: (p) => p.toJson(),
        ),
      );

      // ── 服务端启动 ──
      final serverContainer = buildServerContainer();
      await serverContainer.read(syncServerControllerProvider.notifier).start();
      final httpPort = serverContainer.read(syncServerControllerProvider).httpPort!;

      // ── 客户端连接（跳过 UDP 发现，手动设 server）──
      final clientContainer = buildClientContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'ServerPC',
            ip: '127.0.0.1',
            httpPort: httpPort,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      // ── 客户端请求同步 ──
      await clientContainer
          .read(syncClientControllerProvider.notifier)
          .requestSync();

      final clientState = clientContainer.read(syncClientControllerProvider);
      expect(clientState.phase, SyncPhase.received);
      expect(clientState.deduplicatedData, isNotNull);
      expect(clientState.deduplicatedData!.modelProviders, isNotEmpty);

      // ── 客户端执行导入 ──
      final imported = await clientContainer
          .read(syncClientControllerProvider.notifier)
          .executeImport();

      expect(imported, isTrue);
      final clientProviders = clientContainer.read(llmProviderConfigsProvider);
      expect(clientProviders.length, 1);
      expect(clientProviders.first.name, 'TestProvider');
      expect(clientProviders.first.models.length, 1);
    });

    test('服务端无数据 → 客户端 phase=noNewData', () async {
      // 服务端无种子数据
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
          selectedCategories: {SyncCategory.providers},
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

    test('服务端和客户端有相同 provider → 去重后 phase=noNewData', () async {
      final provider = _provider();
      final providerJson = VersionedJsonStorage.encodeObjectList(
        items: [provider],
        toJson: (p) => p.toJson(),
      );

      // 服务端和客户端都种子相同的 provider
      await serverPrefs.setString('settings.llm_model_configs', providerJson);
      await clientPrefs.setString('settings.llm_model_configs', providerJson);

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
          selectedCategories: {SyncCategory.providers},
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
  });
}
