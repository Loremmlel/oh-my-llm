import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';

/// 捕获发送请求的 mock BaseClient，返回 200 StreamedResponse。
///
/// [MockClient] 返回 [http.Response]（高层），但 [CustomHeadersHttpClient]
/// 通过 [http.BaseClient.send] 工作，需要 [http.StreamedResponse]。
class _MockBaseClient extends http.BaseClient {
  _MockBaseClient(this.onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}

http.StreamedResponse _okResponse() {
  return http.StreamedResponse(Stream.value([]), 200);
}

void main() {
  group('CustomHeadersHttpClient', () {
    test('用户定义 header 覆盖请求中已有的同名 header', () async {
      final client = CustomHeadersHttpClient(
        _MockBaseClient((request) async {
          expect(request.headers['User-Agent'], 'my-custom-agent');
          return _okResponse();
        }),
        {'User-Agent': 'my-custom-agent'},
      );

      final request = http.Request('GET', Uri.parse('https://example.com'))
        ..headers['User-Agent'] = 'default-agent';
      await client.send(request);
      client.close();
    });

    test('updateHeaders 后后续请求携带新 header', () async {
      var callCount = 0;
      final client = CustomHeadersHttpClient(
        _MockBaseClient((request) async {
          callCount++;
          if (callCount == 1) {
            expect(request.headers['X-Old'], 'old-value');
            expect(request.headers.containsKey('X-New'), isFalse);
          } else {
            expect(request.headers.containsKey('X-Old'), isFalse);
            expect(request.headers['X-New'], 'new-value');
          }
          return _okResponse();
        }),
        {'X-Old': 'old-value'},
      );

      // 第一次请求携带旧 header
      await client.send(
        http.Request('GET', Uri.parse('https://example.com/1')),
      );

      // 更新 header
      client.updateHeaders({'X-New': 'new-value'});

      // 第二次请求携带新 header
      await client.send(
        http.Request('GET', Uri.parse('https://example.com/2')),
      );

      client.close();
    });
  });
}
