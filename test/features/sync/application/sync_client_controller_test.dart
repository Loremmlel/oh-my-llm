import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_crypto.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_protocol_coordinator.dart';
import 'package:oh_my_llm/features/sync/data/security/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/session/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

import '../../../helpers/async/async_test_signals.dart';
import 'sync_test_fakes.dart';

/// 与本地协议区间重叠、可正常建立连接的发现服务端。
const compatibleServer = DiscoveredServer(
  deviceName: '服务器',
  ip: '192.168.1.2',
  httpPort: 8080,
  serverId: 'srv-1',
);

/// 协议区间与本地不重叠的旧版本服务端。
const incompatibleServer = DiscoveredServer(
  deviceName: '旧设备',
  ip: '192.168.1.3',
  httpPort: 8080,
  serverId: 'srv-old',
  protocolRange: SyncProtocolRange(minimum: 1, maximum: 3),
);

final _requestDocument = SettingsTransferDocument(
  sections: {'presetPrompts': <Object?>[]},
);

const _testOnlySyncGroup = SettingsSyncGroupDescriptor(
  id: SettingsSyncGroupId('testOnly'),
  label: '测试扩展',
  order: 6,
  sensitivity: SettingsSyncSensitivity.credentialBearing,
);

List<SettingsSyncGroupDescriptor> _dynamicGroups() => [
  ...defaultSettingsSyncGroups,
  _testOnlySyncGroup,
];

ProviderContainer _buildContainer({
  required FakeSyncClientTransport transport,
  required ScriptedSyncClientProtocol protocol,
  required FakeSettingsSyncFacade settingsFacade,
}) {
  return ProviderContainer(
    overrides: [
      syncClientTransportProvider.overrideWithValue(transport),
      settingsSyncFacadeProvider.overrideWithValue(settingsFacade),
      syncClientControllerProvider.overrideWith(
        () => SyncClientController(protocol: protocol),
      ),
    ],
  );
}

/// 启动发现并等待兼容服务端建立连接。
Future<void> connectToCompatibleServer({
  required ProviderContainer container,
  required FakeSyncClientTransport transport,
}) async {
  await container.read(syncClientControllerProvider.notifier).startDiscovery();
  final connected = waitForProviderState(
    container: container,
    provider: syncClientControllerProvider,
    matches: (s) => s.phase == SyncPhase.connected,
    description: '同步连接建立',
  );
  transport.add(compatibleServer);
  await connected;
}

void main() {
  test('构建从设置目录读取分组描述并保留顺序', () {
    final transport = FakeSyncClientTransport();
    final facade = FakeSettingsSyncFacade(
      availableGroups: [
        const SettingsSyncGroupDescriptor(
          id: SettingsSyncGroupId('second'),
          label: '第二项',
          order: 20,
          sensitivity: SettingsSyncSensitivity.standard,
        ),
        const SettingsSyncGroupDescriptor(
          id: SettingsSyncGroupId('first'),
          label: '第一项',
          order: 10,
          sensitivity: SettingsSyncSensitivity.credentialBearing,
        ),
      ],
    );
    final container = _buildContainer(
      transport: transport,
      protocol: ScriptedSyncClientProtocol(),
      settingsFacade: facade,
    );
    addTearDown(container.dispose);

    final state = container.read(syncClientControllerProvider);

    expect(state.availableGroups, facade.availableGroups);
    expect(state.availableGroups.map((group) => group.id.value), [
      'second',
      'first',
    ]);
    expect(
      () => state.availableGroups.add(facade.availableGroups.first),
      throwsUnsupportedError,
    );
  });

  test('全选复制所有分组描述 ID，未知分组保持状态不变', () {
    final transport = FakeSyncClientTransport();
    final facade = FakeSettingsSyncFacade(availableGroups: _dynamicGroups());
    final container = _buildContainer(
      transport: transport,
      protocol: ScriptedSyncClientProtocol(),
      settingsFacade: facade,
    );
    addTearDown(container.dispose);

    final notifier = container.read(syncClientControllerProvider.notifier);
    notifier.selectAllGroups();
    final selected = container.read(syncClientControllerProvider);
    final selectedBeforeUnknown = selected;

    expect(
      selected.selectedGroups,
      _dynamicGroups().map((group) => group.id).toSet(),
    );

    notifier.toggleGroup(const SettingsSyncGroupId('unknown'));

    expect(
      container.read(syncClientControllerProvider),
      same(selectedBeforeUnknown),
    );
  });

  group('服务端断开检测', () {
    late ProviderContainer container;
    late FakeSyncClientTransport transport;

    setUp(() {
      transport = FakeSyncClientTransport();
      container = ProviderContainer(
        overrides: [
          syncClientTransportProvider.overrideWithValue(transport),
          settingsSyncFacadeProvider.overrideWithValue(
            FakeSettingsSyncFacade(),
          ),
          syncPairingRepositoryProvider.overrideWithValue(
            FakePairingRepository(),
          ),
          syncCryptoProvider.overrideWithValue(CryptographySyncCrypto()),
          syncClockProvider.overrideWithValue(FakeSyncClock()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await transport.close();
        await waitForProviderState(
          container: container,
          provider: syncClientControllerProvider,
          matches: (s) => s.phase == SyncPhase.error || s.server == null,
          description: '同步连接关闭',
        );
      });
    });

    test('已连接后广播流关闭时清空会话状态并弹错误气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);
      await notifier.startDiscovery();

      final connected = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.connected,
        description: '同步连接建立',
      );
      transport.add(compatibleServer);
      await connected;

      final disconnected = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.error || s.server == null,
        description: '同步连接关闭',
      );
      await transport.close();
      await disconnected;

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.server, isNull);
      expect(state.sourceDeviceName, isNull);
      expect(state.isPaired, isFalse);
      expect(state.preparedImport, isNull);
      expect(state.errorMessage, '服务端已断开，请重新搜索');

      final bubbles = container.read(notificationBubblesProvider);
      expect(bubbles, hasLength(1));
      expect(bubbles.single.message, '服务端已断开，请重新搜索');
      expect(bubbles.single.type, NotificationBubbleType.error);
    });

    test('搜索未发现时流关闭只置错误文案，不弹气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);
      await notifier.startDiscovery();

      final discoveryEnded = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.error,
        description: '发现流程结束',
      );
      await transport.close();
      await discoveryEnded;

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.server, isNull);
      expect(state.errorMessage, '未发现服务端，请确认服务端已启动且在同一局域网内');
      expect(container.read(notificationBubblesProvider), isEmpty);
    });
  });

  group('客户端协议状态（脚本化协议注入）', () {
    late ProviderContainer container;
    late FakeSyncClientTransport transport;
    late ScriptedSyncClientProtocol protocol;
    late FakeSettingsSyncFacade settingsFacade;

    setUp(() {
      transport = FakeSyncClientTransport();
      protocol = ScriptedSyncClientProtocol();
      settingsFacade = FakeSettingsSyncFacade();
      container = _buildContainer(
        transport: transport,
        protocol: protocol,
        settingsFacade: settingsFacade,
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await transport.close();
        await waitForProviderState(
          container: container,
          provider: syncClientControllerProvider,
          matches: (s) => s.phase == SyncPhase.error || s.server == null,
          description: '同步连接关闭',
        );
      });
    });

    test('配对成功时协议收到裁剪后的配对码并回到 connected', () async {
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      await container
          .read(syncClientControllerProvider.notifier)
          .pairWithCode(' 123456 ');

      expect(protocol.pairedCode, '123456');
      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.isPaired, isTrue);
    });

    test('发现不兼容设备时显示版本错误且不调用 isPaired', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);
      await notifier.startDiscovery();

      final failed = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.error,
        description: '不兼容设备被拒绝',
      );
      transport.add(incompatibleServer);
      await failed;

      expect(protocol.isPairedCount, 0);
      expect(
        container.read(syncClientControllerProvider).errorMessage,
        '设备版本不兼容，需要更新',
      );
    });

    test('发现流出错时显示发现过程错误', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);
      await notifier.startDiscovery();

      final failed = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.error,
        description: '发现过程出错',
      );
      transport.addError(StateError('boom'));
      await failed;

      expect(
        container.read(syncClientControllerProvider).errorMessage,
        '发现过程出错: Bad state: boom',
      );
    });

    test('配对被协议拒绝时显示协议用户文案', () async {
      protocol.pairError = const SyncProtocolFailure(
        SyncProtocolErrorCode.pairingRejected,
      );
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      await container
          .read(syncClientControllerProvider.notifier)
          .pairWithCode('123456');

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '配对失败，请检查配对码后重试');
      expect(protocol.paired, isFalse);
    });

    test('配对传输失败时显示传输用户文案', () async {
      protocol.pairError = const SyncTransportException('传输失败');
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      await container
          .read(syncClientControllerProvider.notifier)
          .pairWithCode('123456');

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '传输失败');
    });

    test('请求使用精确 stable group ID，并以 prepared import 进入 received', () async {
      protocol.requestResult = _requestDocument;
      final prepared = ScriptedSettingsSyncPreparedImport(
        summaries: const [
          SettingsSyncSummaryItem(label: '预设', trailingText: '新增 1 项'),
        ],
      );
      settingsFacade.preparedImport = prepared;
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));
      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.received);
      expect(state.preparedImport, same(prepared));
      expect(protocol.requestedGroups, {const SettingsSyncGroupId('presets')});
      expect(settingsFacade.requestedGroups, {
        const SettingsSyncGroupId('presets'),
      });
      expect(protocol.requestedSensitiveConfirmation, isFalse);
    });

    test('prepared import 无变化时进入 noNewData', () async {
      protocol.requestResult = _requestDocument;
      settingsFacade.preparationError = const SettingsSyncNoNewDataException();
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));
      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.noNewData);
      expect(state.preparedImport, isNull);
    });

    test('响应包含未请求 section 时在任何写入前进入错误', () async {
      protocol.requestResult = SettingsTransferDocument(
        sections: {'modelProviders': <Object?>[]},
      );
      settingsFacade.preparationError = const SettingsSyncPreparationException(
        '同步数据包含未请求的配置项',
      );
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );

      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));
      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '同步数据包含未请求的配置项');
      expect(state.preparedImport, isNull);
    });

    test('请求完成前切换分组仍使用请求开始时捕获的 group 子集', () async {
      protocol.requestResult = _requestDocument;
      final prepared = ScriptedSettingsSyncPreparedImport(
        summaries: const [
          SettingsSyncSummaryItem(label: '预设', trailingText: '新增 1 项'),
        ],
      );
      settingsFacade.preparedImport = prepared;
      protocol.requestGate = Completer<void>();
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));
      final requestFuture = notifier.requestSync();
      await waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (state) => state.phase == SyncPhase.syncing,
        description: '同步请求开始',
      );

      notifier.toggleGroup(const SettingsSyncGroupId('prompts'));
      protocol.requestGate!.complete();
      await requestFuture;

      expect(settingsFacade.requestedGroups, {
        const SettingsSyncGroupId('presets'),
      });
      expect(
        container.read(syncClientControllerProvider).phase,
        SyncPhase.received,
      );
    });

    for (final code in [
      SyncProtocolErrorCode.pairingRequired,
      SyncProtocolErrorCode.pairingRejected,
    ]) {
      test('请求遇到 ${code.name} 时撤销配对并显示协议用户文案', () async {
        final failure = SyncProtocolFailure(code);
        protocol.paired = true;
        protocol.requestError = failure;
        await connectToCompatibleServer(
          container: container,
          transport: transport,
        );
        final notifier = container.read(syncClientControllerProvider.notifier);
        notifier.toggleGroup(const SettingsSyncGroupId('presets'));

        await notifier.requestSync();

        final state = container.read(syncClientControllerProvider);
        expect(state.phase, SyncPhase.error);
        expect(state.errorMessage, failure.userMessage);
        expect(state.isPaired, isFalse);
        expect(protocol.forgetCount, 1);
        expect(protocol.paired, isFalse);
      });
    }

    test('普通协议失败时保留配对状态', () async {
      protocol.paired = true;
      protocol.requestError = const SyncProtocolFailure(
        SyncProtocolErrorCode.sessionExpired,
      );
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '同步会话已过期，请重新连接');
      expect(state.isPaired, isTrue);
      expect(protocol.forgetCount, 0);
      expect(protocol.paired, isTrue);
    });

    test('请求传输失败时显示传输用户文案且不撤销配对', () async {
      protocol.paired = true;
      protocol.requestError = const SyncTransportException('传输失败');
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '传输失败');
      expect(state.isPaired, isTrue);
      expect(protocol.forgetCount, 0);
    });

    test('请求未预期异常时显示同步失败文案', () async {
      protocol.requestError = StateError('boom');
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '同步失败: Bad state: boom');
    });

    test('切换分组清除敏感确认、待导入状态与错误', () async {
      protocol.requestResult = _requestDocument;
      settingsFacade.preparedImport = ScriptedSettingsSyncPreparedImport(
        summaries: const [
          SettingsSyncSummaryItem(label: '预设', trailingText: '新增 1 项'),
        ],
      );
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));
      notifier.confirmSensitiveRequest();
      await notifier.requestSync();

      notifier.toggleGroup(const SettingsSyncGroupId('prompts'));

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.selectedGroups, {
        SettingsSyncGroupId('presets'),
        SettingsSyncGroupId('prompts'),
      });
      expect(state.sensitiveRequestConfirmed, isFalse);
      expect(state.preparedImport, isNull);
      expect(state.errorMessage, isNull);
    });

    test('请求被取消后晚到的数据不改变空闲状态且清空会话', () async {
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleGroup(const SettingsSyncGroupId('presets'));

      protocol.requestGate = Completer<void>();
      final requestFuture = notifier.requestSync();
      notifier.cancelAndReset();
      protocol.requestGate!.complete();
      await requestFuture;

      expect(
        container.read(syncClientControllerProvider),
        SyncClientState(availableGroups: defaultSettingsSyncGroups),
      );
      expect(protocol.clearSessionsCount, 1);
    });

    test('配对被取消后晚到的成功不改变空闲状态', () async {
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);

      protocol.pairGate = Completer<void>();
      final pairFuture = notifier.pairWithCode('123456');
      notifier.cancelAndReset();
      protocol.pairGate!.complete();
      await pairFuture;

      expect(
        container.read(syncClientControllerProvider),
        SyncClientState(availableGroups: defaultSettingsSyncGroups),
      );
    });
  });

  group('服务端 catalog 安全校验', () {
    test('服务端按本地 descriptor 重算敏感性并拒绝未知 group', () async {
      final serverStore = FakePairingRepository(
        identity: const SyncPeerIdentity(
          id: 'server-id',
          displayName: 'Server',
        ),
      );
      final clientStore = FakePairingRepository(
        identity: const SyncPeerIdentity(
          id: 'client-id',
          displayName: 'Client',
        ),
      );
      final clientView = FakeSettingsSyncFacade(
        availableGroups: const [
          SettingsSyncGroupDescriptor(
            id: SettingsSyncGroupId('presets'),
            label: '预设',
            order: 0,
            sensitivity: SettingsSyncSensitivity.standard,
          ),
        ],
      );
      final serverFacade = FakeSettingsSyncFacade(
        availableGroups: const [
          SettingsSyncGroupDescriptor(
            id: SettingsSyncGroupId('presets'),
            label: '预设',
            order: 0,
            sensitivity: SettingsSyncSensitivity.credentialBearing,
          ),
        ],
      );
      expect(
        clientView.availableGroups.single.sensitivity,
        SettingsSyncSensitivity.standard,
      );
      expect(
        serverFacade.availableGroups.single.sensitivity,
        SettingsSyncSensitivity.credentialBearing,
      );
      final server = SyncServerProtocolCoordinator(
        pairingRepository: serverStore,
        crypto: CryptographySyncCrypto(),
        clock: FakeSyncClock(),
        settingsFacade: serverFacade,
      );
      final code = await server.generatePairingCode();
      final client = SyncClientProtocolCoordinator(
        transport: _LoopbackSyncClientTransport(server),
        pairingRepository: clientStore,
        crypto: CryptographySyncCrypto(),
        clock: FakeSyncClock(),
      );
      final peer = const DiscoveredServer(
        deviceName: 'Server',
        ip: '127.0.0.1',
        httpPort: 8080,
        serverId: 'server-id',
      );
      await client.pair(server: peer, code: code, displayName: 'Client');

      await expectLater(
        client.requestSettings(
          server: peer,
          groups: {SettingsSyncGroupId('presets')},
          confirmedSensitive: false,
        ),
        throwsA(
          isA<SyncProtocolFailure>().having(
            (failure) => failure.code,
            'code',
            SyncProtocolErrorCode.sensitiveConfirmationRequired,
          ),
        ),
      );
      expect(serverFacade.exportCount, 0);

      final exported = await client.requestSettings(
        server: peer,
        groups: {SettingsSyncGroupId('presets')},
        confirmedSensitive: true,
      );
      expect(exported.sections, isEmpty);
      expect(serverFacade.exportCount, 1);

      await expectLater(
        client.requestSettings(
          server: peer,
          groups: {SettingsSyncGroupId('futureGroup')},
          confirmedSensitive: true,
        ),
        throwsA(
          isA<SyncProtocolFailure>().having(
            (failure) => failure.code,
            'code',
            SyncProtocolErrorCode.malformedMessage,
          ),
        ),
      );
      expect(serverFacade.exportCount, 1);
    });
  });
}

final class _LoopbackSyncClientTransport implements SyncClientTransport {
  _LoopbackSyncClientTransport(this.server);

  final SyncServerProtocolCoordinator server;

  @override
  Stream<DiscoveredServer> discoverServers() => const Stream.empty();

  @override
  Future<SyncProtocolMessage> send({
    required DiscoveredServer server,
    required SyncProtocolMessage request,
  }) async => (await this.server.handle(request)).message;
}
