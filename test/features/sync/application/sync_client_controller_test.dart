import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble_data.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_crypto.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

import '../../../helpers/async_test_signals.dart';
import 'sync_test_fakes.dart';

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
}
