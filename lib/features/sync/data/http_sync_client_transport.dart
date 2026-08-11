import 'dart:async';

import 'package:http/http.dart' as http;

import '../application/ports/sync_client_transport.dart';
import '../domain/models/sync_protocol_failure.dart';
import '../domain/models/sync_protocol_message.dart';
import 'sync_udp_discovery.dart';

/// 基于 peer HTTP client 与 UDP discovery 的 Sync 客户端传输实现。
final class HttpSyncClientTransport implements SyncClientTransport {
  HttpSyncClientTransport(this._client, {SyncUdpDiscovery? discovery})
    : _discovery = discovery ?? SyncUdpDiscovery.system;

  final http.Client _client;
  final SyncUdpDiscovery _discovery;

  @override
  Stream<DiscoveredServer> discoverServers() async* {
    final session = _discovery.listenForServers();
    try {
      await session.ready;
      yield* session.servers;
    } finally {
      await session.close();
    }
  }

  @override
  Future<SyncProtocolMessage> send({
    required DiscoveredServer server,
    required SyncProtocolMessage request,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('http://${server.ip}:${server.httpPort}/sync'),
            body: SyncProtocolCodec.encode(request),
            headers: const {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
      final decoded = SyncProtocolCodec.decode(response.body);
      if (decoded case SyncProtocolDecodeFailure(:final failure)) {
        throw SyncTransportException(failure.userMessage);
      }
      final responseMessage = (decoded as SyncProtocolDecodeSuccess).message;
      if (responseMessage case SyncProtocolError(:final failure)) {
        throw failure;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncTransportException('服务端响应异常（HTTP ${response.statusCode}）');
      }
      if (responseMessage.requestId != request.requestId) {
        throw const SyncTransportException('响应格式错误');
      }
      return responseMessage;
    } on TimeoutException catch (error) {
      throw SyncTransportException('请求超时，请检查网络连接', cause: error);
    } on SyncTransportException {
      rethrow;
    } on SyncProtocolFailure {
      rethrow;
    } catch (error) {
      throw SyncTransportException('同步失败: $error', cause: error);
    }
  }
}
