@Tags(['udp'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/sync/data/sync_udp_discovery.dart';
import 'package:oh_my_llm/features/sync/data/sync_udp_sessions.dart';

/// 单个 loopback UDP smoke。
///
/// 监听 socket 显式绑定 127.0.0.1 与 OS 分配端口，广播同样走 loopback 并
/// 指向监听端口，不依赖局域网广播路由。整个用例无 intentional 等待：
/// 广播在 startBroadcasting 内同步发出，2 秒 timeout 只是失败边界。
/// 依赖真实 UDP socket，在部分 CI / 虚拟化环境（Docker、GitHub Actions
/// Windows runner、部分防火墙配置）可能不可用，统一打 `@Tags(['udp'])`
/// 以便按需排除：
///
/// ```bash
/// flutter test --exclude-tags=udp
/// ```
void main() {
  test('loopback listener 能收到 system broadcaster 的真实 UDP 公告', () async {
    final discovery = SyncUdpDiscovery.system;
    final listener = discovery.listenForServers(
      bindAddress: InternetAddress.loopbackIPv4,
      discoveryPort: 0,
      timeout: const Duration(seconds: 2),
    );
    SyncUdpBroadcastSession? broadcaster;
    addTearDown(() async {
      await broadcaster?.stop();
      await listener.close();
      await listener.done;
    });

    await listener.ready;
    final received = listener.servers
        .firstWhere((server) => server.serverId == 'udp-loopback-smoke')
        .timeout(const Duration(seconds: 2));

    broadcaster = await discovery.startBroadcasting(
      httpPort: 54321,
      deviceName: 'Test-PC',
      serverId: 'udp-loopback-smoke',
      broadcastAddress: InternetAddress.loopbackIPv4,
      discoveryPort: listener.port,
      broadcastInterval: const Duration(minutes: 1),
    );

    final server = await received;
    expect(server.deviceName, 'Test-PC');
    expect(server.httpPort, 54321);
    expect(server.ip, InternetAddress.loopbackIPv4.address);
  });
}
