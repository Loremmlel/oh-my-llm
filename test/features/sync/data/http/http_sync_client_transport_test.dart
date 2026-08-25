import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/data/http/http_sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_message.dart';

const server = DiscoveredServer(
  deviceName: '服务器',
  ip: '127.0.0.1',
  httpPort: 8080,
  serverId: 'server-1',
);
const request = PairingChallengeRequest(
  requestId: 'request-1',
  clientIdentity: 'client-1',
);

PairingChallengeResponse response({String requestId = 'request-1'}) =>
    PairingChallengeResponse(
      requestId: requestId,
      pairingId: 'pairing-1',
      challengeNonce: 'bm9uY2U=',
      serverIdentity: 'server-1',
    );

/// 用 [handler] 构造传输，并保证 MockClient 在测试结束时关闭。
HttpSyncClientTransport makeTransport(MockClientHandler handler) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return HttpSyncClientTransport(client);
}

void main() {
  test('合法响应返回匹配 requestId 的 typed message', () async {
    final expected = response();
    final client = MockClient((incoming) async {
      expect(incoming.method, 'POST');
      expect(incoming.url.path, '/sync');
      expect(incoming.headers['Content-Type'], 'application/json');
      final decoded = SyncProtocolCodec.decode(incoming.body);
      expect(decoded, isA<SyncProtocolDecodeSuccess>());
      expect((decoded as SyncProtocolDecodeSuccess).message, request);
      return http.Response(
        SyncProtocolCodec.encode(expected),
        200,
        headers: const {'Content-Type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final result = await HttpSyncClientTransport(client)
        .send(server: server, request: request);

    expect(result, expected);
  });

  test('malformed body 映射为公开格式错误', () async {
    final transport = makeTransport(
      (incoming) async => http.Response('not json', 200),
    );

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.userMessage,
          'userMessage',
          '同步请求格式无效',
        ),
      ),
    );
  });

  test('typed protocol error 保持 SyncProtocolFailure 类型', () async {
    const protocolError = SyncProtocolError(
      requestId: 'request-1',
      failure: SyncProtocolFailure(SyncProtocolErrorCode.pairingRejected),
    );
    final transport = makeTransport(
      (incoming) async => http.Response(
        SyncProtocolCodec.encode(protocolError),
        200,
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncProtocolFailure>().having(
          (e) => e.userMessage,
          'userMessage',
          '配对失败，请检查配对码后重试',
        ),
      ),
    );
  });

  test('非 2xx typed response 映射 HTTP 状态错误', () async {
    final transport = makeTransport(
      (incoming) async => http.Response(
        SyncProtocolCodec.encode(response()),
        503,
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.userMessage,
          'userMessage',
          '服务端响应异常（HTTP 503）',
        ),
      ),
    );
  });

  test('响应 requestId 不匹配时拒绝响应', () async {
    final transport = makeTransport(
      (incoming) async => http.Response(
        SyncProtocolCodec.encode(response(requestId: 'other-request')),
        200,
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.userMessage,
          'userMessage',
          '响应格式错误',
        ),
      ),
    );
  });

  test('请求超时立即映射为公开提示并保留 TimeoutException 原因', () async {
    final transport = makeTransport((_) => throw TimeoutException('synthetic'));

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncTransportException>()
            .having((e) => e.userMessage, 'userMessage', '请求超时，请检查网络连接')
            .having((e) => e.cause, 'cause', isA<TimeoutException>()),
      ),
    );
  });

  test('通用网络异常映射为包含错误文本的同步失败提示', () async {
    final transport = makeTransport((_) => throw StateError('offline'));

    await expectLater(
      transport.send(server: server, request: request),
      throwsA(
        isA<SyncTransportException>()
            .having(
              (e) => e.userMessage,
              'userMessage',
              allOf(contains('同步失败'), contains('offline')),
            )
            .having((e) => e.cause, 'cause', isA<StateError>()),
      ),
    );
  });
}
