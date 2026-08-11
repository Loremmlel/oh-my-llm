import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/models/discovered_server.dart';
import 'sync_udp_announcement_codec.dart';

export '../domain/models/discovered_server.dart';

const MethodChannel _multicastChannel = MethodChannel(
  'yuzu.shiki.oh_my_llm/multicast_lock',
);

/// Android 上获取 MulticastLock 以允许接收 UDP 广播包。
Future<void> _acquireMulticastLock() async {
  if (!Platform.isAndroid) return;
  try {
    await _multicastChannel.invokeMethod('acquire');
  } catch (e) {
    debugPrint('获取 MulticastLock 失败: $e');
  }
}

/// 释放 Android MulticastLock。
Future<void> _releaseMulticastLock() async {
  if (!Platform.isAndroid) return;
  try {
    await _multicastChannel.invokeMethod('release');
  } catch (e) {
    debugPrint('释放 MulticastLock 失败: $e');
  }
}

/// UDP 广播发现层。
///
/// 服务端定期广播自身信息到子网，客户端监听广播以发现服务端。
/// Android 上自动管理 MulticastLock 生命周期。
class SyncUdpDiscovery {
  SyncUdpDiscovery._();

  static const int discoveryPort = 47280;
  static const SyncUdpAnnouncementCodec _codec = SyncUdpAnnouncementCodec();

  /// 开始周期性 UDP 广播，返回停止函数。
  ///
  /// [broadcastAddress] 可选的定向广播地址；未传入时回退到 255.255.255.255。
  /// [broadcastInterval] 广播周期；测试可传短周期加速用例，生产保持默认 2s。
  static Future<Future<void> Function()> startBroadcasting({
    required int httpPort,
    required String deviceName,
    required String serverId,
    InternetAddress? broadcastAddress,
    Duration broadcastInterval = const Duration(seconds: 2),
  }) async {
    await _acquireMulticastLock();

    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      await _releaseMulticastLock();
      rethrow;
    }
    socket.broadcastEnabled = true;

    final targetAddress =
        broadcastAddress ?? InternetAddress('255.255.255.255');
    final payload = _codec.encode(
      httpPort: httpPort,
      deviceName: deviceName,
      serverId: serverId,
    );

    void sendBroadcast() {
      try {
        socket.send(payload, targetAddress, discoveryPort);
      } catch (e) {
        debugPrint('UDP 广播发送失败: $e');
      }
    }

    sendBroadcast();
    final timer = Timer.periodic(broadcastInterval, (_) => sendBroadcast());

    return () async {
      timer.cancel();
      socket.close();
      await _releaseMulticastLock();
    };
  }

  /// 监听局域网内的服务端广播，返回发现流。
  ///
  /// 取消订阅时会同步清理 socket 和 MulticastLock，不会泄漏资源。
  static Stream<DiscoveredServer> listenForServers({
    // 服务端每 2s 广播一次，6s 约覆盖 3 个广播周期，用于更快感知服务端停止。
    Duration timeout = const Duration(seconds: 6),
  }) {
    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    StreamSubscription? socketSub;
    var cancelled = false;

    final controller = StreamController<DiscoveredServer>(
      onCancel: () async {
        cancelled = true;
        timeoutTimer?.cancel();
        await socketSub?.cancel();
        socket?.close();
        await _releaseMulticastLock();
      },
    );

    () async {
      try {
        await _acquireMulticastLock();
        if (cancelled) {
          await _releaseMulticastLock();
          return;
        }

        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
        );
        if (cancelled) {
          socket!.close();
          await _releaseMulticastLock();
          return;
        }
        socket!.broadcastEnabled = true;

        void resetTimeout() {
          timeoutTimer?.cancel();
          timeoutTimer = Timer(timeout, () async {
            socketSub?.cancel();
            socket?.close();
            await _releaseMulticastLock();
            controller.close();
          });
        }

        resetTimeout();

        socketSub = socket!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket?.receive();
          if (datagram == null) return;

          final server = _codec.decode(
            data: datagram.data,
            sourceAddress: datagram.address.address,
          );
          if (server == null) return;
          controller.add(server);
          resetTimeout();
        });
      } catch (e) {
        if (!cancelled) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }
}
