import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_message.dart';
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

// ── 辅助类 ──────────────────────────────────────────────────────────────────

/// 固定响应的测试 HTTP 服务端。
class _SyncHttpTestServer {
  late SyncHttpServer _server;
  late int port;

  Future<void> start({required SyncMessage Function(SyncMessage) handler}) async {
    _server = SyncHttpServer();
    final syncHandler = SyncHttpHandler(
      onRequest: (request) async => handler(request),
    );
    port = await _server.start(handlers: [syncHandler]);
  }

  Future<void> close() async {
    if (_server.isRunning) await _server.stop();
  }
}

/// 测试用子类：覆盖 build() 以注入预设 state。
class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this._seed);

  final SyncClientState _seed;

  @override
  SyncClientState build() => _seed;
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('SyncClientController 状态机', () {
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

    test('build 初始状态为 idle', () {
      final container = buildContainer();
      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.idle);
      expect(state.server, isNull);
      expect(state.selectedCategories, isEmpty);
    });

    test('toggleCategory 添加和移除分类', () {
      final container = buildContainer();
      final notifier = container.read(syncClientControllerProvider.notifier);

      notifier.toggleCategory(SyncCategory.providers);
      expect(
        container.read(syncClientControllerProvider).selectedCategories,
        {SyncCategory.providers},
      );

      notifier.toggleCategory(SyncCategory.presets);
      expect(
        container.read(syncClientControllerProvider).selectedCategories,
        {SyncCategory.providers, SyncCategory.presets},
      );

      notifier.toggleCategory(SyncCategory.providers);
      expect(
        container.read(syncClientControllerProvider).selectedCategories,
        {SyncCategory.presets},
      );
    });

    test('selectAllCategories 选中所有分类', () {
      final container = buildContainer();
      container.read(syncClientControllerProvider.notifier).selectAllCategories();
      expect(
        container.read(syncClientControllerProvider).selectedCategories,
        SyncCategory.values.toSet(),
      );
    });

    test('cancelAndReset 回到 idle，清除 server 和 categories', () {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: const DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: 12345,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );
      container.read(syncClientControllerProvider.notifier).cancelAndReset();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.idle);
      expect(state.server, isNull);
      expect(state.selectedCategories, isEmpty);
    });

    test('resetToConnected 清除 deduplicatedData 和 errorMessage，phase=connected', () {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.received,
          errorMessage: 'some error',
          deduplicatedData: SettingsExportData(
            modelProviders: [_provider()],
            memoryPrompts: const [],
            presetPrompts: const [],
            templatePrompts: const [],
            fixedPromptSequences: const [],
          ),
        ),
      );
      container.read(syncClientControllerProvider.notifier).resetToConnected();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.errorMessage, isNull);
      expect(state.deduplicatedData, isNull);
    });
  });

  group('SyncClientController.requestSync 分支', () {
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

    test('无 server 时提前返回，phase 不变', () async {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      expect(container.read(syncClientControllerProvider).phase, SyncPhase.connected);
    });

    test('空 categories 时提前返回，phase 不变', () async {
      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: const DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: 12345,
          ),
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      expect(container.read(syncClientControllerProvider).phase, SyncPhase.connected);
    });

    test('正常路径：响应 settingsSyncResponse + 新数据 → phase=received', () async {
      final exportData = SettingsExportData(
        modelProviders: [_provider()],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      );

      final testServer = _SyncHttpTestServer();
      await testServer.start(
        handler: (request) => SyncMessage.response(
          type: SyncMessageType.settingsSyncResponse,
          requestId: request.requestId,
          payload: {'data': exportData.toJsonString()},
        ),
      );
      addTearDown(() => testServer.close());

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: testServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.received);
      expect(state.deduplicatedData, isNotNull);
      expect(state.deduplicatedData!.modelProviders, isNotEmpty);
    });

    test('响应格式错误（tryDecode 返回 null）→ phase=error', () async {
      final rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      rawServer.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('not valid json{{{')
          ..close();
      });
      addTearDown(() => rawServer.close(force: true));

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: rawServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '响应格式错误');
    });

    test('响应 type=error → phase=error，errorMessage 来自 payload', () async {
      final testServer = _SyncHttpTestServer();
      await testServer.start(
        handler: (request) => SyncMessage.error(
          requestId: request.requestId,
          code: 3,
          message: '服务端忙',
        ),
      );
      addTearDown(() => testServer.close());

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: testServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '服务端忙');
    });

    test('响应未知 type → phase=error', () async {
      final testServer = _SyncHttpTestServer();
      await testServer.start(
        handler: (request) => SyncMessage.response(
          type: 'mystery_type',
          requestId: request.requestId,
          payload: {},
        ),
      );
      addTearDown(() => testServer.close());

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: testServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, contains('未知的响应类型'));
    });

    test('data 字段解析失败 → phase=error', () async {
      final testServer = _SyncHttpTestServer();
      await testServer.start(
        handler: (request) => SyncMessage.response(
          type: SyncMessageType.settingsSyncResponse,
          requestId: request.requestId,
          payload: {'data': 'not-valid-export-data{{{'},
        ),
      );
      addTearDown(() => testServer.close());

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: testServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '数据解析失败');
    });

    test('去重后无新数据 → phase=noNewData', () async {
      final emptyData = const SettingsExportData(
        modelProviders: [],
        memoryPrompts: [],
        presetPrompts: [],
        templatePrompts: [],
        fixedPromptSequences: [],
      );

      final testServer = _SyncHttpTestServer();
      await testServer.start(
        handler: (request) => SyncMessage.response(
          type: SyncMessageType.settingsSyncResponse,
          requestId: request.requestId,
          payload: {'data': emptyData.toJsonString()},
        ),
      );
      addTearDown(() => testServer.close());

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: testServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      expect(
        container.read(syncClientControllerProvider).phase,
        SyncPhase.noNewData,
      );
    });

    test('超时 → phase=error（30s）', () async {
      final rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      rawServer.listen((_) {});
      addTearDown(() => rawServer.close(force: true));

      final container = buildContainer(
        seed: SyncClientState(
          phase: SyncPhase.connected,
          server: DiscoveredServer(
            deviceName: 'Test',
            ip: '127.0.0.1',
            httpPort: rawServer.port,
          ),
          selectedCategories: {SyncCategory.providers},
        ),
      );

      await container.read(syncClientControllerProvider.notifier).requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, contains('超时'));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
