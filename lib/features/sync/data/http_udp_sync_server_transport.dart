import '../application/ports/sync_server_transport.dart';
import 'sync_http_handler.dart';
import 'sync_http_server.dart';
import 'sync_udp_discovery.dart';
import 'sync_udp_sessions.dart';

/// 基于现有 HTTP router 和 UDP broadcaster 的 Sync 服务端传输实现。
final class HttpUdpSyncServerTransport implements SyncServerTransport {
  HttpUdpSyncServerTransport({SyncUdpDiscovery? discovery})
    : _discovery = discovery ?? SyncUdpDiscovery.system;

  final SyncUdpDiscovery _discovery;
  final SyncHttpServer _httpServer = SyncHttpServer();
  SyncUdpBroadcastSession? _broadcastSession;

  @override
  Future<SyncServerHandle> start(SyncServerStartRequest request) async {
    final handlers = [
      SyncHttpHandler(onRequest: request.onRequest),
      ...request.mediaRoutes,
    ];
    final httpPort = await _httpServer.start(handlers: handlers);
    try {
      _broadcastSession = await _discovery.startBroadcasting(
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
    final session = _broadcastSession;
    _broadcastSession = null;
    if (session != null) {
      // 先停广播再等会话 done（stop 与 done 共享同一清理 Future，顺序保证
      // 资源释放完成），最后才关 HTTP：UDP 必须先于 HTTP shutdown。
      await session.stop();
      await session.done;
    }
    await _httpServer.stop();
  }
}
