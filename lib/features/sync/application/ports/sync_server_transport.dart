import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/http/http_route_handler.dart';
import '../../domain/models/sync_protocol_message.dart';

/// 启动 Sync 服务端所需的运行期参数。
final class SyncServerStartRequest {
  const SyncServerStartRequest({
    required this.deviceName,
    required this.serverId,
    required this.broadcastAddress,
    required this.onRequest,
    required this.mediaRoutes,
  });

  final String deviceName;
  final String serverId;
  final InternetAddress? broadcastAddress;
  final Future<SyncProtocolMessage> Function(SyncProtocolMessage request)
  onRequest;
  final List<HttpRouteHandler> mediaRoutes;
}

/// 已运行 Sync 服务端的最小公开信息。
final class SyncServerHandle {
  const SyncServerHandle({required this.httpPort});

  final int httpPort;
}

/// Sync 服务端 HTTP/UDP 生命周期边界。
abstract interface class SyncServerTransport {
  Future<SyncServerHandle> start(SyncServerStartRequest request);

  /// 必须可重复调用，并按 UDP、HTTP 的既有顺序释放资源。
  Future<void> stop();
}

/// 必须由 app composition 或测试显式绑定的服务端传输实现。
final syncServerTransportProvider = Provider<SyncServerTransport>((ref) {
  throw StateError('SyncServerTransport 尚未由应用组合层绑定');
});
