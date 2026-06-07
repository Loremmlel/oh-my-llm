import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/sync/data/sync_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_message.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

void main() {
  group('SyncHttpServer', () {
    late SyncHttpServer server;

    setUp(() {
      server = SyncHttpServer();
    });

    tearDown(() async {
      if (server.isRunning) {
        await server.stop();
      }
    });

    SyncHttpHandler createEchoHandler() {
      return SyncHttpHandler(
        onRequest: (request) async {
          return SyncMessage.response(
            type: '${request.type}_echo',
            requestId: request.requestId,
            payload: {'echo': request.payload},
          );
        },
      );
    }

    Future<int> startWithEcho() async {
      return server.start(handlers: [createEchoHandler()]);
    }

    test('start 绑定随机端口并返回端口号，isRunning 为 true', () async {
      final port = await startWithEcho();

      expect(port, greaterThan(0));
      expect(server.isRunning, isTrue);
    });

    test('stop 后 isRunning 为 false', () async {
      await startWithEcho();

      await server.stop();

      expect(server.isRunning, isFalse);
    });

    test('POST /sync 请求被路由到 SyncHttpHandler，响应包含回调返回的 SyncMessage',
        () async {
      final port = await startWithEcho();
      final request = SyncMessage.request(
        type: SyncMessageType.settingsSyncRequest,
        payload: const {'categories': ['providers']},
      );

      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: const {'Content-Type': 'application/json'},
        body: SyncMessageCodec.encode(request),
      );

      expect(response.statusCode, 200);
      final decoded = SyncMessageCodec.tryDecode(response.body);
      expect(decoded, isNotNull);
      expect(decoded!.type, '${SyncMessageType.settingsSyncRequest}_echo');
      expect(decoded.requestId, request.requestId);
      expect(decoded.payload['echo'], request.payload);
    });

    test('无匹配 handler 的请求返回 404', () async {
      final port = await startWithEcho();

      // GET /sync → 不存在匹配的 handler（SyncHttpHandler 只匹配 POST /sync）
      final getResp = await http.get(Uri.parse('http://127.0.0.1:$port/sync'));
      expect(getResp.statusCode, 404);

      // POST /other → 不存在匹配的 handler
      final postResp = await http.post(
        Uri.parse('http://127.0.0.1:$port/other'),
        headers: const {'Content-Type': 'application/json'},
        body: SyncMessageCodec.encode(
          SyncMessage.request(type: 't', payload: const {}),
        ),
      );
      expect(postResp.statusCode, 404);
    });

    test('请求体非法 JSON 返回错误 SyncMessage（code=2）', () async {
      final port = await startWithEcho();

      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/sync'),
        headers: const {'Content-Type': 'application/json'},
        body: 'this is not json',
      );

      expect(response.statusCode, 200);
      final decoded = SyncMessageCodec.tryDecode(response.body);
      expect(decoded, isNotNull);
      expect(decoded!.type, SyncMessageType.error);
      expect(decoded.payload['code'], SyncErrorCode.payloadParseFailed);
    });

    test('多次 start/stop 不泄漏资源', () async {
      for (var i = 0; i < 3; i++) {
        final port = await startWithEcho();
        expect(server.isRunning, isTrue);

        // 发一个请求验证 server 真的在监听
        final response = await http.post(
          Uri.parse('http://127.0.0.1:$port/sync'),
          headers: const {'Content-Type': 'application/json'},
          body: SyncMessageCodec.encode(
            SyncMessage.request(type: 't', payload: {'i': i}),
          ),
        );
        expect(response.statusCode, 200);

        await server.stop();
        expect(server.isRunning, isFalse);
      }
    });

    test('并发两个 POST 请求，两个响应都正确', () async {
      final port = await startWithEcho();

      final requestA = SyncMessage.request(
        type: 'type_a',
        payload: const {'which': 'a'},
      );
      final requestB = SyncMessage.request(
        type: 'type_b',
        payload: const {'which': 'b'},
      );

      final results = await Future.wait([
        http.post(
          Uri.parse('http://127.0.0.1:$port/sync'),
          headers: const {'Content-Type': 'application/json'},
          body: SyncMessageCodec.encode(requestA),
        ),
        http.post(
          Uri.parse('http://127.0.0.1:$port/sync'),
          headers: const {'Content-Type': 'application/json'},
          body: SyncMessageCodec.encode(requestB),
        ),
      ]);

      expect(results.length, 2);
      final decodedA = SyncMessageCodec.tryDecode(results[0].body);
      final decodedB = SyncMessageCodec.tryDecode(results[1].body);
      expect(decodedA, isNotNull);
      expect(decodedB, isNotNull);
      // 顺序可能交换，按 requestId 匹配
      final byId = {decodedA!.requestId: decodedA, decodedB!.requestId: decodedB};
      expect(byId[requestA.requestId]!.type, 'type_a_echo');
      expect(byId[requestB.requestId]!.type, 'type_b_echo');
    });
  });
}
