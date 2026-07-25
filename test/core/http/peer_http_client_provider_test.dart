import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';

void main() {
  group('peerHttpClientProvider', () {
    test('返回纯 http.Client，非 CustomHeadersHttpClient', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final client = container.read(peerHttpClientProvider);
      // peer client 应是原始 http.Client，不是 CustomHeadersHttpClient
      expect(client, isA<http.Client>());
      expect(client.runtimeType.toString(), isNot(contains('CustomHeaders')));
    });

    test('peer client 的请求不携带自定义 header', () async {
      String? capturedUserAgent;
      final mockClient = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response('{}', 200);
      });

      final container = ProviderContainer(
        overrides: [peerHttpClientProvider.overrideWithValue(mockClient)],
      );
      addTearDown(container.dispose);

      // peer client 不经过 CustomHeadersHttpClient，不会注入自定义 header
      final client = container.read(peerHttpClientProvider);
      await client.get(Uri.parse('http://192.168.1.5:8080/api/media/list/'));

      // MockClient 不传 User-Agent，所以是 null（不是自定义值）
      expect(capturedUserAgent, isNull);
    });
  });
}
