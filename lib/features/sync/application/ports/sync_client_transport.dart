import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/discovered_server.dart';
import '../../domain/models/sync_message.dart';

/// Sync 客户端传输失败。
///
/// [userMessage] 已经过滤，可直接展示给用户；底层 HTTP、UDP 实现细节不应由
/// controller 重新解析。
final class SyncTransportException implements Exception {
  const SyncTransportException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

/// 局域网 Sync 客户端的发现和请求传输边界。
abstract interface class SyncClientTransport {
  Stream<DiscoveredServer> discoverServers();

  Future<SyncMessage> send({
    required DiscoveredServer server,
    required SyncMessage request,
  });
}

/// 必须由 app composition 或测试显式绑定的客户端传输实现。
final syncClientTransportProvider = Provider<SyncClientTransport>((ref) {
  throw StateError('SyncClientTransport 尚未由应用组合层绑定');
});
