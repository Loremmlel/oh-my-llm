import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';

void main() {
  group('信任域分离', () {
    test('LLM client 的请求携带自定义 header', () async {
      final container = ProviderContainer(
        overrides: [
          customHeadersMapProvider.overrideWith(
            (ref) => {'X-API-Key': 'sk-secret-key'},
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(customHeadersSyncProvider);

      final llmClient = container.read(httpClientProvider);
      expect(
        llmClient.currentHeaders,
        containsPair('X-API-Key', 'sk-secret-key'),
      );
    });

    test('peer client 请求不携带 LLM 自定义 header', () async {
      var peerRequestHadApiKey = false;
      final mockClient = MockClient((request) async {
        if (request.headers.containsKey('X-API-Key')) {
          peerRequestHadApiKey = true;
        }
        return http.Response('{}', 200);
      });

      final container = ProviderContainer(
        overrides: [
          customHeadersMapProvider.overrideWith(
            (ref) => {'X-API-Key': 'sk-should-not-leak'},
          ),
          peerHttpClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      container.read(customHeadersSyncProvider);

      final peerClient = container.read(peerHttpClientProvider);
      await peerClient.get(Uri.parse('http://192.168.1.5:8080/sync'));

      expect(
        peerRequestHadApiKey,
        isFalse,
        reason: 'peer 请求不应携带 LLM 自定义 header',
      );
    });
  });
}
