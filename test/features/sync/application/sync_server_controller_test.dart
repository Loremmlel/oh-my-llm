import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
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
    models: const [],
  );
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('SyncServerController', () {
    late SharedPreferences preferences;
    late AppDatabase database;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      database = AppDatabase.inMemory();
    });

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(() {
        container.dispose();
        database.close();
      });
      return container;
    }

    test('build 从 SharedPreferences 读取 deviceName，无存储时回退到 hostname', () async {
      // 无存储时回退到 Platform.localHostname
      final c1 = buildContainer();
      expect(c1.read(syncServerControllerProvider).deviceName, Platform.localHostname);
      c1.dispose();

      // 有存储时使用存储值
      SharedPreferences.setMockInitialValues({'sync.device_name': '我的设备'});
      preferences = await SharedPreferences.getInstance();
      final c2 = buildContainer();
      expect(c2.read(syncServerControllerProvider).deviceName, '我的设备');
    });

    test('start 后 isRunning 为 true，httpPort 非 null', () async {
      final container = buildContainer();
      await container.read(syncServerControllerProvider.notifier).start();

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.httpPort, isNotNull);
    });

    test('stop 后 isRunning=false, httpPort=null, servedRequestCount=0', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);

      await notifier.start();
      expect(container.read(syncServerControllerProvider).isRunning, isTrue);

      await notifier.stop();

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.httpPort, isNull);
      expect(state.servedRequestCount, 0);
    });

    test('重复 start 是幂等的', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);

      await notifier.start();
      final port1 = container.read(syncServerControllerProvider).httpPort;

      await notifier.start();
      final port2 = container.read(syncServerControllerProvider).httpPort;

      expect(port1, port2);
    });

    test('updateDeviceName 持久化到 SharedPreferences', () async {
      final container = buildContainer();
      await container.read(syncServerControllerProvider.notifier).updateDeviceName('新设备名');

      expect(preferences.getString('sync.device_name'), '新设备名');
      expect(container.read(syncServerControllerProvider).deviceName, '新设备名');
    });

    test('updateDeviceName 在运行中时重启服务', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);

      await notifier.start();
      final port1 = container.read(syncServerControllerProvider).httpPort;

      await notifier.updateDeviceName('新名字');

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.deviceName, '新名字');
      expect(state.httpPort, isNot(port1));
    });

    test('updateDeviceName 连续快速调用不会启动多个 server', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);

      await notifier.start();

      await Future.wait([
        notifier.updateDeviceName('设备A'),
        notifier.updateDeviceName('设备B'),
      ]);

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.deviceName, '设备B');
    });

    test('POST 未知消息类型返回 error（code=1）', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);
      await notifier.start();
      final port = container.read(syncServerControllerProvider).httpPort!;

      final request = SyncMessage.request(
        type: 'unknown_type',
        payload: {},
      );
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: SyncMessageCodec.encode(request),
      );

      final message = SyncMessageCodec.tryDecode(response.body)!;
      expect(message.type, SyncMessageType.error);
      expect(message.payload['code'], SyncErrorCode.unknownType);
    });

    test('POST settingsSyncRequest 返回对应分类数据，servedRequestCount 递增', () async {
      final provider = _provider();
      SharedPreferences.setMockInitialValues({
        'settings.llm_model_configs': VersionedJsonStorage.encodeObjectList(
          items: [provider],
          toJson: (p) => p.toJson(),
        ),
      });
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);
      await notifier.start();
      final port = container.read(syncServerControllerProvider).httpPort!;

      final request = SyncMessage.request(
        type: SyncMessageType.settingsSyncRequest,
        payload: {
          'categories': [SyncCategory.providers.payloadKey],
        },
      );
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: SyncMessageCodec.encode(request),
      );

      final message = SyncMessageCodec.tryDecode(response.body)!;
      expect(message.type, SyncMessageType.settingsSyncResponse);

      final dataJson = message.payload['data'] as String;
      final data = jsonDecode(dataJson) as Map<String, dynamic>;
      final providers = data['modelProviders'] as List;
      expect(providers, isNotEmpty);

      expect(container.read(syncServerControllerProvider).servedRequestCount, 1);
    });
  });
}
