import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_crypto.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/data/security/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
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
  protocolRange: SyncProtocolRange(minimum: 1, maximum: 2),
);

/// 包含一个新预设的导出数据，用于验证请求成功路径。
final presetExport = SettingsExportData(
  modelProviders: [],
  memoryPrompts: [],
  presetPrompts: [
    PresetPrompt(
      id: 'preset-new',
      name: '新预设',
      messages: [],
      updatedAt: DateTime(2026, 1, 1),
    ),
  ],
  templatePrompts: [],
  fixedPromptSequences: [],
);

/// 全空导出数据，模拟去重后已无新内容的场景。
const emptyExport = SettingsExportData(
  modelProviders: [],
  memoryPrompts: [],
  presetPrompts: [],
  templatePrompts: [],
  fixedPromptSequences: [],
);

/// 构造注入脚本化协议的测试容器：控制器只依赖协议操作，不触碰配对仓库、
/// 加密或时钟，因此无需任何 crypto 设置。
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
///
/// 先注册连接建立 predicate 再推送发现事件，等待由可观察的状态信号完成。
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
  test('客户端安全状态不会包含 pairing code 或 session secret', () {
    final state = SyncClientState(
      phase: SyncPhase.connected,
      server: const DiscoveredServer(
        deviceName: '服务器',
        ip: '192.168.1.2',
        httpPort: 8080,
        serverId: 'stable-server',
        protocolRange: SyncProtocolRange.local,
      ),
      selectedCategories: {SyncCategory.presets},
      isPaired: true,
    );

    expect(state.isPaired, isTrue);
    expect(state.selectedCategories, {SyncCategory.presets});
    expect(state.props.join(), isNot(contains('token')));
    expect(state.props.join(), isNot(contains('secret')));
  });

  test('分类变更会清除仅本次的敏感接收确认', () {
    final state = SyncClientState(
      selectedCategories: {SyncCategory.providers},
      sensitiveRequestConfirmed: true,
    );

    final changed = state.copyWith(
      selectedCategories: {SyncCategory.presets},
      sensitiveRequestConfirmed: false,
    );

    expect(changed.sensitiveRequestConfirmed, isFalse);
  });

  group('服务端断开检测', () {
    late ProviderContainer container;
    late FakeSyncClientTransport transport;

    setUp(() {
      transport = FakeSyncClientTransport();
      container = ProviderContainer(
        overrides: [
          syncClientTransportProvider.overrideWithValue(transport),
          syncPairingRepositoryProvider.overrideWithValue(
            FakePairingRepository(),
          ),
          syncCryptoProvider.overrideWithValue(CryptographySyncCrypto()),
          syncClockProvider.overrideWithValue(FakeSyncClock()),
        ],
      );
      addTearDown(container.dispose);
      // 兜底收口：用例中途失败时也先关闭广播流、等 controller 进入终态，
      // 再销毁容器，避免残留的流监听挂在未关闭的 StreamController 上。
      // 注册在 dispose 之后，tearDown 逆序执行，先收口再销毁。
      // StreamController.close() 对已关闭的 controller 幂等（SDK 保证：
      // 仅首次调用生效），与用例体内的 transport.close() 双收口安全。
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

    test('已连接后广播流关闭 → 清空会话状态并弹错误气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);

      await notifier.startDiscovery();

      // 先注册连接建立 predicate 再推送发现事件，等待由可观察的状态信号
      // 完成，不再依赖「flush 微任务」的时机假设。
      final connected = waitForProviderState(
        container: container,
        provider: syncClientControllerProvider,
        matches: (s) => s.phase == SyncPhase.connected,
        description: '同步连接建立',
      );
      transport.add(
        const DiscoveredServer(
          deviceName: '服务器',
          ip: '192.168.1.2',
          httpPort: 8080,
          serverId: 'srv-1',
        ),
      );
      await connected;

      final connectedState = container.read(syncClientControllerProvider);
      expect(connectedState.phase, SyncPhase.connected);
      expect(connectedState.server, isNotNull);

      // 断开同理：先注册终态 predicate 再关闭广播流。
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
      expect(state.deduplicatedData, isNull);
      expect(state.errorMessage, '服务端已断开，请重新搜索');

      final bubbles = container.read(notificationBubblesProvider);
      expect(bubbles, hasLength(1));
      expect(bubbles.single.message, '服务端已断开，请重新搜索');
      expect(bubbles.single.type, NotificationBubbleType.error);
    });

    test('搜索未发现时流关闭 → 只置错误文案，不弹气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);

      await notifier.startDiscovery();

      // 先注册发现结束 predicate 再关闭广播流，等待由状态信号完成。
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
      // 兜底收口：与「服务端断开检测」组一致，先关闭广播流、等 controller
      // 进入终态，再销毁容器。
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

    test('配对成功：协议收到裁剪后的配对码，状态回到 connected 且 isPaired 为 true', () async {
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);

      await notifier.pairWithCode(' 123456 ');

      expect(protocol.pairedCode, '123456');
      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.isPaired, isTrue);
    });

    test('发现不兼容设备 → 显示版本错误且不调用 isPaired', () async {
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

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '设备版本不兼容，需要更新');
      expect(protocol.isPairedCount, 0);
    });

    test('发现流出错 → 显示发现过程错误', () async {
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

    test('配对被协议拒绝 → 显示协议用户文案', () async {
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

    test('配对传输失败 → 显示传输用户文案', () async {
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

    test('请求返回新预设 → received 并携带去重后数据', () async {
      protocol.requestResult = presetExport;
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.received);
      expect(state.deduplicatedData?.presetPrompts.single.name, '新预设');
      expect(protocol.requestedCategories, {SyncCategory.presets});
      expect(protocol.requestedSensitiveConfirmation, isFalse);
    });

    test('请求返回的内容已被去重过滤 → noNewData', () async {
      protocol.requestResult = presetExport;
      settingsFacade.deduplicatedResult = emptyExport;
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.noNewData);
      expect(state.deduplicatedData, isNull);
    });

    for (final code in [
      SyncProtocolErrorCode.pairingRequired,
      SyncProtocolErrorCode.pairingRejected,
    ]) {
      test('请求遇到 ${code.name} → 撤销配对并显示协议用户文案', () async {
        final failure = SyncProtocolFailure(code);
        protocol.paired = true;
        protocol.requestError = failure;
        await connectToCompatibleServer(
          container: container,
          transport: transport,
        );
        final notifier = container.read(syncClientControllerProvider.notifier);
        notifier.toggleCategory(SyncCategory.presets);

        await notifier.requestSync();

        final state = container.read(syncClientControllerProvider);
        expect(state.phase, SyncPhase.error);
        expect(state.errorMessage, failure.userMessage);
        expect(state.isPaired, isFalse);
        expect(protocol.forgetCount, 1);
        expect(protocol.paired, isFalse);
      });
    }

    test('普通协议失败保留配对状态', () async {
      protocol.paired = true;
      protocol.requestError = const SyncProtocolFailure(
        SyncProtocolErrorCode.sessionExpired,
      );
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '同步会话已过期，请重新连接');
      expect(state.isPaired, isTrue);
      expect(protocol.forgetCount, 0);
      expect(protocol.paired, isTrue);
    });

    test('请求传输失败 → 显示传输用户文案且不撤销配对', () async {
      protocol.paired = true;
      protocol.requestError = const SyncTransportException('传输失败');
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '传输失败');
      expect(state.isPaired, isTrue);
      expect(protocol.forgetCount, 0);
    });

    test('请求未预期异常 → 显示同步失败文案', () async {
      protocol.requestError = StateError('boom');
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      await notifier.requestSync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.errorMessage, '同步失败: Bad state: boom');
    });

    // 把控制器推进到「已接收 + 敏感确认 + 错误文案」三者并存的瞬时状态：
    // 请求成功得到数据，再让配对失败产生错误，验证清除类操作的契约。
    Future<void> reachStaleState() async {
      protocol.paired = true;
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);
      notifier.confirmSensitiveRequest();
      protocol.requestResult = presetExport;
      await notifier.requestSync();
      protocol.pairError = const SyncProtocolFailure(
        SyncProtocolErrorCode.pairingRejected,
      );
      await notifier.pairWithCode('123456');
    }

    test('切换分类清除敏感确认、旧数据与错误', () async {
      await reachStaleState();
      final notifier = container.read(syncClientControllerProvider.notifier);

      notifier.toggleCategory(SyncCategory.prompts);

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.selectedCategories, {
        SyncCategory.presets,
        SyncCategory.prompts,
      });
      expect(state.sensitiveRequestConfirmed, isFalse);
      expect(state.deduplicatedData, isNull);
      expect(state.errorMessage, isNull);
    });

    test('全选清除瞬时确认/数据/错误并选择全部类别', () async {
      await reachStaleState();
      final notifier = container.read(syncClientControllerProvider.notifier);

      notifier.selectAllCategories();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.selectedCategories, SyncCategory.values.toSet());
      expect(state.sensitiveRequestConfirmed, isFalse);
      expect(state.deduplicatedData, isNull);
      expect(state.errorMessage, isNull);
    });

    test('resetToConnected 清除瞬时状态但保留服务端与选择', () async {
      await reachStaleState();
      final notifier = container.read(syncClientControllerProvider.notifier);

      notifier.resetToConnected();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.connected);
      expect(state.server, isNotNull);
      expect(state.selectedCategories, {SyncCategory.presets});
      expect(state.sensitiveRequestConfirmed, isFalse);
      expect(state.deduplicatedData, isNull);
      expect(state.errorMessage, isNull);
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

      expect(container.read(syncClientControllerProvider), SyncClientState());
    });

    test('请求被取消后晚到的数据不改变空闲状态且清空会话', () async {
      await connectToCompatibleServer(
        container: container,
        transport: transport,
      );
      final notifier = container.read(syncClientControllerProvider.notifier);
      notifier.toggleCategory(SyncCategory.presets);

      protocol.requestGate = Completer<void>();
      final requestFuture = notifier.requestSync();
      notifier.cancelAndReset();
      protocol.requestGate!.complete();
      await requestFuture;

      expect(container.read(syncClientControllerProvider), SyncClientState());
      expect(protocol.clearSessionsCount, 1);
    });
  });
}
