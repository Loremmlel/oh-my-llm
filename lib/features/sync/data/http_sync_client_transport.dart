import 'dart:async';

import 'package:http/http.dart' as http;

import '../application/ports/sync_client_transport.dart';
import '../domain/models/sync_message.dart';
import 'sync_udp_discovery.dart';

/// 基于 peer HTTP client 与 UDP discovery 的 Sync 客户端传输实现。
final class HttpSyncClientTransport implements SyncClientTransport {
  const HttpSyncClientTransport(this._client);

  final http.Client _client;

  @override
  Stream<DiscoveredServer> discoverServers() {
    return SyncUdpDiscovery.listenForServers();
  }

  @override
  Future<SyncMessage> send({
    required DiscoveredServer server,
    required SyncMessage request,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('http://${server.ip}:${server.httpPort}/sync'),
            body: SyncMessageCodec.encode(request),
            headers: const {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncTransportException('服务端响应异常（HTTP ${response.statusCode}）');
      }
      final responseMessage = SyncMessageCodec.tryDecode(response.body);
      if (responseMessage == null) {
        throw const SyncTransportException('响应格式错误');
      }
      return responseMessage;
    } on TimeoutException catch (error) {
      throw SyncTransportException('请求超时，请检查网络连接', cause: error);
    } on SyncTransportException {
      rethrow;
    } catch (error) {
      throw SyncTransportException('同步失败: $error', cause: error);
    }
  }
}
