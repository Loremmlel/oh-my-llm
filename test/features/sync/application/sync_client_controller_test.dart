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
    });

    /// 让已排队的微任务（流事件分发、async 监听器）执行完毕。
    Future<void> flushAsync() => Future<void>.delayed(Duration.zero);

    test('已连接后广播流关闭 → 清空会话状态并弹错误气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);

      await notifier.startDiscovery();
      transport.add(
        const DiscoveredServer(
          deviceName: '服务器',
          ip: '192.168.1.2',
          httpPort: 8080,
          serverId: 'srv-1',
        ),
      );
      await flushAsync();

      final connected = container.read(syncClientControllerProvider);
      expect(connected.phase, SyncPhase.connected);
      expect(connected.server, isNotNull);

      await transport.close();
      await flushAsync();

      final disconnected = container.read(syncClientControllerProvider);
      expect(disconnected.phase, SyncPhase.error);
      expect(disconnected.server, isNull);
      expect(disconnected.sourceDeviceName, isNull);
      expect(disconnected.isPaired, isFalse);
      expect(disconnected.deduplicatedData, isNull);
      expect(disconnected.errorMessage, '服务端已断开，请重新搜索');

      final bubbles = container.read(notificationBubblesProvider);
      expect(bubbles, hasLength(1));
      expect(bubbles.single.message, '服务端已断开，请重新搜索');
      expect(bubbles.single.type, NotificationBubbleType.error);
    });

    test('搜索未发现时流关闭 → 只置错误文案，不弹气泡', () async {
      final notifier = container.read(syncClientControllerProvider.notifier);

      await notifier.startDiscovery();
      await transport.close();
      await flushAsync();

      final state = container.read(syncClientControllerProvider);
      expect(state.phase, SyncPhase.error);
      expect(state.server, isNull);
      expect(state.errorMessage, '未发现服务端，请确认服务端已启动且在同一局域网内');
      expect(container.read(notificationBubblesProvider), isEmpty);
    });
  });
}
