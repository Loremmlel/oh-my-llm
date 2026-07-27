import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/http/http_route_handler.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/network_interface_provider.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_media_route_factory.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_server_transport.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/network_interface_info.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

final class _FakeSettingsFacade implements SettingsSyncFacade {
  SettingsSyncSelection? exportedSelection;
  SettingsExportData? incoming;
  SettingsExportData? imported;

  @override
  SettingsExportData deduplicateIncoming(SettingsExportData data) {
    incoming = data;
    return data;
  }

  @override
  SettingsExportData exportSelected(SettingsSyncSelection selection) {
    exportedSelection = selection;
    return const SettingsExportData(
      modelProviders: [],
      memoryPrompts: [],
      presetPrompts: [],
      templatePrompts: [],
      fixedPromptSequences: [],
    );
  }

  @override
  Future<bool> importDeduplicated(SettingsExportData data) async {
    imported = data;
    return true;
  }
}

final class _FakeClientTransport implements SyncClientTransport {
  final discovery = StreamController<DiscoveredServer>();
  SyncMessage? sentRequest;
  late SyncMessage response;

  @override
  Stream<DiscoveredServer> discoverServers() => discovery.stream;

  @override
  Future<SyncMessage> send({
    required DiscoveredServer server,
    required SyncMessage request,
  }) async {
    sentRequest = request;
    return response;
  }
}

final class _FakeServerTransport implements SyncServerTransport {
  SyncServerStartRequest? startRequest;
  var stopCount = 0;

  @override
  Future<SyncServerHandle> start(SyncServerStartRequest request) async {
    startRequest = request;
    return const SyncServerHandle(httpPort: 49152);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

final class _FakeMediaRouteFactory implements SyncMediaRouteFactory {
  var createCount = 0;

  @override
  Future<List<HttpRouteHandler>> createRoutes() async {
    createCount++;
    return const [];
  }
}

void main() {
  late SharedPreferences preferences;
  late _FakeSettingsFacade settingsFacade;
  late _FakeClientTransport clientTransport;
  late _FakeServerTransport serverTransport;
  late _FakeMediaRouteFactory mediaRouteFactory;
  late ProviderContainer container;
  late ProviderSubscription<SyncClientState> clientSubscription;
  late ProviderSubscription<SyncServerState> serverSubscription;
  var serverStarted = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    settingsFacade = _FakeSettingsFacade();
    clientTransport = _FakeClientTransport();
    serverTransport = _FakeServerTransport();
    mediaRouteFactory = _FakeMediaRouteFactory();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsSyncFacadeProvider.overrideWithValue(settingsFacade),
        syncClientTransportProvider.overrideWithValue(clientTransport),
        syncServerTransportProvider.overrideWithValue(serverTransport),
        syncMediaRouteFactoryProvider.overrideWithValue(mediaRouteFactory),
        availableInterfacesProvider.overrideWith(
          (ref) => Future.value(const <NetworkInterfaceInfo>[]),
        ),
      ],
    );
    clientSubscription = container.listen(
      syncClientControllerProvider,
      (_, _) {},
    );
    serverSubscription = container.listen(
      syncServerControllerProvider,
      (_, _) {},
    );
  });

  tearDown(() async {
    if (serverStarted) {
      await container.read(syncServerControllerProvider.notifier).stop();
    }
    clientSubscription.close();
    serverSubscription.close();
    container.dispose();
    unawaited(clientTransport.discovery.close());
  });

  test('客户端经 fake transport 完成发现、接收和导入', () async {
    final data = const SettingsExportData(
      modelProviders: [],
      memoryPrompts: [],
      presetPrompts: [],
      templatePrompts: [],
      fixedPromptSequences: [],
      autoRetrySettings: AutoRetrySettings(maxRetryCount: 1),
    );
    clientTransport.response = SyncMessage.response(
      type: SyncMessageType.settingsSyncResponse,
      requestId: 'response-id',
      payload: {'data': data.toJsonString()},
    );
    final controller = container.read(syncClientControllerProvider.notifier);

    await controller.startDiscovery();
    clientTransport.discovery.add(
      const DiscoveredServer(
        deviceName: '测试设备',
        ip: '192.168.1.5',
        httpPort: 8080,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.toggleCategory(SyncCategory.providers);

    await controller.requestSync();
    expect(clientTransport.sentRequest, isNotNull);
    expect(
      container.read(syncClientControllerProvider).phase,
      SyncPhase.received,
    );
    final imported = await container
        .read(syncClientControllerProvider.notifier)
        .executeImport();
    expect(imported, isTrue);
    expect(settingsFacade.imported?.toJsonString(), data.toJsonString());
  });

  test('服务端经 fake transport 暴露回调并导出选中分类', () async {
    final controller = container.read(syncServerControllerProvider.notifier);
    final starting = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(mediaRouteFactory.createCount, 1);
    expect(serverTransport.startRequest, isNotNull);
    await starting.timeout(const Duration(seconds: 2));
    serverStarted = true;

    final request = serverTransport.startRequest;
    expect(request, isNotNull);
    expect(mediaRouteFactory.createCount, 1);
    expect(container.read(syncServerControllerProvider).httpPort, 49152);

    final response = await request!.onRequest(
      SyncMessage.request(
        type: SyncMessageType.settingsSyncRequest,
        payload: {
          'categories': [
            SyncCategory.providers.payloadKey,
            SyncCategory.prompts.payloadKey,
          ],
        },
      ),
    );
    expect(response.type, SyncMessageType.settingsSyncResponse);
    expect(settingsFacade.exportedSelection?.providers, isTrue);
    expect(settingsFacade.exportedSelection?.prompts, isTrue);
    expect(settingsFacade.exportedSelection?.presets, isFalse);
    expect(container.read(syncServerControllerProvider).servedRequestCount, 1);
  });
}
