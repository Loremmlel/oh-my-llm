import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/application/network_interface_provider.dart';
import 'package:oh_my_llm/features/sync/domain/models/network_interface_info.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_message.dart';

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

    ProviderContainer buildContainer({
      Future<List<NetworkInterfaceInfo>> Function()? interfaces,
    }) {
      final container = ProviderContainer(
        overrides: [
          ...appCompositionOverrides(),
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
          if (interfaces != null)
            availableInterfacesProvider.overrideWith((ref) => interfaces()),
        ],
      );
      final subscription = container.listen(
        syncServerControllerProvider,
        (_, _) {},
      );
      addTearDown(() async {
        if (container.exists(syncServerControllerProvider)) {
          await container.read(syncServerControllerProvider.notifier).stop();
        }
        subscription.close();
        container.dispose();
        database.close();
      });
      return container;
    }

    test('SyncServerState 按网卡字段和可观察值比较', () {
      expect(
        SyncServerState(
          isRunning: true,
          deviceName: '设备',
          httpPort: 8080,
          servedRequestCount: 1,
          selectedInterface: NetworkInterfaceInfo(
            name: 'Wi-Fi',
            ip: '192.168.1.2',
          ),
        ),
        SyncServerState(
          isRunning: true,
          deviceName: '设备',
          httpPort: 8080,
          servedRequestCount: 1,
          selectedInterface: NetworkInterfaceInfo(
            name: 'Wi-Fi',
            ip: '192.168.1.2',
          ),
        ),
      );
      expect(
        SyncServerState(servedRequestCount: 1),
        isNot(SyncServerState(servedRequestCount: 2)),
      );
    });

    test('运行中的同步服务在观察者移除后存活，直到显式停止', () async {
      final container = ProviderContainer(
        overrides: [
          ...appCompositionOverrides(),
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      final subscription = container.listen(
        syncServerControllerProvider,
        (_, _) {},
      );
      final controller = container.read(syncServerControllerProvider.notifier);
      await controller.start();

      subscription.close();
      await container.pump();
      expect(container.exists(syncServerControllerProvider), isTrue);

      await controller.stop();
      await container.pump();
      expect(container.exists(syncServerControllerProvider), isFalse);
      container.dispose();
    });

    test('container dispose 后原 HTTP 端口不再接受请求', () async {
      final container = ProviderContainer(
        overrides: [
          ...appCompositionOverrides(),
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      final subscription = container.listen(
        syncServerControllerProvider,
        (_, _) {},
      );
      await container.read(syncServerControllerProvider.notifier).start();
      final controller = container.read(syncServerControllerProvider.notifier);
      final port = container.read(syncServerControllerProvider).httpPort!;

      container.dispose();
      subscription.close();
      await controller.shutdownFuture;

      await expectLater(
        http.get(Uri.parse('http://127.0.0.1:$port/sync')),
        throwsA(isA<http.ClientException>()),
      );
      database.close();
    });

    test('start 等待网卡枚举时 stop 不会留下运行会话', () async {
      final interfaces = Completer<List<NetworkInterfaceInfo>>();
      final container = buildContainer(interfaces: () => interfaces.future);
      final controller = container.read(syncServerControllerProvider.notifier);

      final starting = controller.start();
      final stopping = controller.stop();
      interfaces.complete(const []);
      await Future.wait([starting, stopping]);

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.httpPort, isNull);
    });

    test('停止尚未完成时重新 start 会在清理后恢复运行', () async {
      final container = buildContainer();
      final controller = container.read(syncServerControllerProvider.notifier);
      await controller.start();

      final stopping = controller.stop();
      final restarting = controller.start();
      await Future.wait([stopping, restarting]);

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.httpPort, isNotNull);
    });

    test('重复 stop 复用同一停止流程并保持空闲状态', () async {
      final container = buildContainer();
      final controller = container.read(syncServerControllerProvider.notifier);
      await controller.start();

      final firstStop = controller.stop();
      final secondStop = controller.stop();
      expect(identical(firstStop, secondStop), isTrue);
      await Future.wait([firstStop, secondStop]);

      final state = container.read(syncServerControllerProvider);
      expect(state.isRunning, isFalse);
      expect(state.httpPort, isNull);
    });

    test('失败的设备名重启释放旧 keep-alive link', () async {
      var invocationCount = 0;
      final container = ProviderContainer(
        overrides: [
          ...appCompositionOverrides(),
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
          availableInterfacesProvider.overrideWith((ref) {
            invocationCount++;
            if (invocationCount == 1) return Future.value(const []);
            return Future<List<NetworkInterfaceInfo>>.error(
              StateError('网卡枚举失败'),
            );
          }),
        ],
      );
      final subscription = container.listen(
        syncServerControllerProvider,
        (_, _) {},
      );
      final controller = container.read(syncServerControllerProvider.notifier);
      await controller.start();
      container.invalidate(availableInterfacesProvider);

      await controller.updateDeviceName('会失败的重启');
      expect(
        container.read(syncServerControllerProvider).lastError,
        contains('启动失败'),
      );

      subscription.close();
      await container.pump();
      expect(container.exists(syncServerControllerProvider), isFalse);
      container.dispose();
      database.close();
    });

    test('无存储时 deviceName 回退到 hostname', () async {
      final c1 = buildContainer();
      expect(
        c1.read(syncServerControllerProvider).deviceName,
        Platform.localHostname,
      );
    });

    test('有存储时 deviceName 读取存储值', () async {
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

    test(
      'stop 后 isRunning=false, httpPort=null, servedRequestCount=0',
      () async {
        final container = buildContainer();
        final notifier = container.read(syncServerControllerProvider.notifier);

        await notifier.start();
        expect(container.read(syncServerControllerProvider).isRunning, isTrue);

        await notifier.stop();

        final state = container.read(syncServerControllerProvider);
        expect(state.isRunning, isFalse);
        expect(state.httpPort, isNull);
        expect(state.servedRequestCount, 0);
      },
    );

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
      await container
          .read(syncServerControllerProvider.notifier)
          .updateDeviceName('新设备名');

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
      // 重启绑定新端口，证明服务确实重启了
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

    test('POST 旧协议请求返回 public unsupportedProtocol', () async {
      final container = buildContainer();
      final notifier = container.read(syncServerControllerProvider.notifier);
      await notifier.start();
      final port = container.read(syncServerControllerProvider).httpPort!;

      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: '{"protocolVersion":1,"kind":"legacy","requestId":"request"}',
      );

      final decoded = SyncProtocolCodec.decode(response.body);
      expect(response.statusCode, HttpStatus.upgradeRequired);
      expect(decoded, isA<SyncProtocolDecodeFailure>());
    });

    test('匿名 settings 请求不会暴露 provider API key', () async {
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

      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: SyncProtocolCodec.encode(
          const EncryptedSyncRequest(
            requestId: 'request',
            sessionId: 'missing',
            sessionToken: 'dG9rZW4=',
            issuedAtMs: 1,
            nonce: 'MTIzNDU2Nzg5MDEy',
            ciphertext: 'YQ==',
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(response.body, isNot(contains('sk-test-key')));
    });

    test('匿名 settings 请求不会增加 servedRequestCount', () async {
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

      await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: {'Content-Type': 'application/json'},
        body: SyncProtocolCodec.encode(
          const EncryptedSyncRequest(
            requestId: 'request',
            sessionId: 'missing',
            sessionToken: 'dG9rZW4=',
            issuedAtMs: 1,
            nonce: 'MTIzNDU2Nzg5MDEy',
            ciphertext: 'YQ==',
          ),
        ),
      );

      expect(
        container.read(syncServerControllerProvider).servedRequestCount,
        0,
      );
    });
  });
}
