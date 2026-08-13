import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/features/sync/data/http/sync_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/http/sync_http_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_failure.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_message.dart';

void main() {
  late SyncHttpServer server;

  setUp(() {
    server = SyncHttpServer();
  });

  tearDown(() => server.stop());

  test('v1 与 malformed 请求被拒绝且没有 snapshot', () async {
    final port = await server.start(
      handlers: [
        SyncHttpHandler(
          onRequest: (message) async => SyncProtocolError(
            requestId: message.requestId,
            failure: const SyncProtocolFailure(
              SyncProtocolErrorCode.pairingRequired,
            ),
          ),
        ),
      ],
    );

    final response = await http.post(
      Uri.parse('http://127.0.0.1:$port/sync'),
      headers: {'Content-Type': 'application/json'},
      body: '{"protocolVersion":1,"kind":"legacy","requestId":"request"}',
    );
    final decoded = SyncProtocolCodec.decode(response.body);

    expect(response.statusCode, HttpStatus.upgradeRequired);
    expect(decoded, isA<SyncProtocolDecodeFailure>());
    expect(response.body, isNot(contains('sk-')));
  });

  test('public protocol failure maps to its HTTP status', () async {
    final port = await server.start(
      handlers: [
        SyncHttpHandler(
          onRequest: (message) async => SyncProtocolError(
            requestId: message.requestId,
            failure: const SyncProtocolFailure(
              SyncProtocolErrorCode.pairingRequired,
            ),
          ),
        ),
      ],
    );
    const request = PairingChallengeRequest(
      requestId: 'request',
      clientIdentity: 'client',
    );

    final response = await http.post(
      Uri.parse('http://127.0.0.1:$port/sync'),
      headers: {'Content-Type': 'application/json'},
      body: SyncProtocolCodec.encode(request),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}
