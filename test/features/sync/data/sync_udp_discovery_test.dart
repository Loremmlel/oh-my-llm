@Tags(['udp'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';

/// UDP 环回测试。
///
/// 依赖本地 UDP 广播到 255.255.255.255:47280 能被同机监听到。
/// 在部分 CI / 虚拟化环境（Docker、GitHub Actions Windows runner、部分防火墙配置）
/// 可能不可用，统一打 `@Tags(['udp'])` 以便按需排除：
///
/// ```bash
/// flutter test --exclude-tags=udp
/// ```
void main() {
  group('SyncUdpDiscovery', () {
    Future<void> Function()? stopBroadcasting;
    StreamSubscription<DiscoveredServer>? listenSub;

    tearDown(() async {
      await listenSub?.cancel();
      listenSub = null;
      await stopBroadcasting?.call();
      stopBroadcasting = null;
      // 给 socket 一点时间释放端口，避免下一个用例绑定 47280 时冲突。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('listenForServers 能收到同机广播', () async {
      // 先启动广播（会立即发一次，再每 2s 发一次）。
      stopBroadcasting = await SyncUdpDiscovery.startBroadcasting(
        httpPort: 54321,
        deviceName: 'Test-PC',
      );

      // 监听 5s 内应至少收到一次。
      final stream = SyncUdpDiscovery.listenForServers(
        timeout: const Duration(seconds: 5),
      );

      final first = await stream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('5s 内未收到广播'),
      );

      expect(first.deviceName, 'Test-PC');
      expect(first.httpPort, 54321);
      // ip 为发送方地址（同机环回可能是 127.0.0.1 或局域网 IP）。
      expect(first.ip, isNotEmpty);
    });

    test('startBroadcasting 停止后不再被新的 listen 收到', () async {
      // 先启动广播并立即停止。
      final stop = await SyncUdpDiscovery.startBroadcasting(
        httpPort: 12345,
        deviceName: 'Gone-PC',
      );
      await stop();
      stopBroadcasting = null; // 避免 tearDown 重复调用

      // 等待超过一个广播周期（2s），确保没有残余包。
      await Future<void>.delayed(const Duration(seconds: 3));

      // 新启动一个 listen，4s 内应收不到任何包（广播方已停）。
      final stream = SyncUdpDiscovery.listenForServers(
        timeout: const Duration(seconds: 4),
      );
      final received = <DiscoveredServer>[];
      listenSub = stream.listen(received.add);

      // 等待 listen 超时关闭（4s）。
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(received, isEmpty);
    });
  });
}
