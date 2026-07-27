import '../application/ports/sync_server_transport.dart';
import 'sync_http_handler.dart';
import 'sync_http_server.dart';
import 'sync_udp_discovery.dart';

/// 基于现有 HTTP router 和 UDP broadcaster 的 Sync 服务端传输实现。
final class HttpUdpSyncServerTransport implements SyncServerTransport {
  final SyncHttpServer _httpServer = SyncHttpServer();
  Future<void> Function()? _stopBroadcasting;

  @override
  Future<SyncServerHandle> start(SyncServerStartRequest request) async {
    final handlers = [
      SyncHttpHandler(onRequest: request.onRequest),
      ...request.mediaRoutes,
    ];
    final httpPort = await _httpServer.start(handlers: handlers);
    try {
      _stopBroadcasting = await SyncUdpDiscovery.startBroadcasting(
        httpPort: httpPort,
        deviceName: request.deviceName,
        serverId: request.serverId,
        broadcastAddress: request.broadcastAddress,
      );
      return SyncServerHandle(httpPort: httpPort);
    } catch (_) {
      await _httpServer.stop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    await _stopBroadcasting?.call();
    _stopBroadcasting = null;
    await _httpServer.stop();
  }
}
