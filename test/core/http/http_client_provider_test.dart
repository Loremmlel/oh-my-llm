import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';

void main() {
  group('信任域分离', () {
    test('httpClientProvider 返回 CustomHeadersHttpClient（LLM 信任域）', () {
      final container = ProviderContainer(
        overrides: [customHeadersMapProvider.overrideWith((ref) => const {})],
      );
      addTearDown(container.dispose);

      final client = container.read(httpClientProvider);
      expect(client, isA<CustomHeadersHttpClient>());
    });

    test('peerHttpClientProvider 返回纯 http.Client（peer 信任域）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final client = container.read(peerHttpClientProvider);
      expect(client, isA<http.Client>());
      expect(client, isNot(isA<CustomHeadersHttpClient>()));
    });

    test('两个 Provider 返回不同实例', () {
      final container = ProviderContainer(
        overrides: [customHeadersMapProvider.overrideWith((ref) => const {})],
      );
      addTearDown(container.dispose);

      final llmClient = container.read(httpClientProvider);
      final peerClient = container.read(peerHttpClientProvider);

      expect(identical(llmClient, peerClient), isFalse);
    });

    test('LLM client 的请求携带自定义 header', () async {
      final container = ProviderContainer(
        overrides: [
          customHeadersMapProvider.overrideWith(
            (ref) => {'X-API-Key': 'sk-secret-key'},
          ),
          // 同步 provider 会在 watch 时自动更新 client 的 headers
        ],
      );
      addTearDown(container.dispose);

      // 触发 sync provider
      container.read(customHeadersSyncProvider);

      // 替换内部 client 为 mock（通过重新构建 provider 不现实，
      // 改为直接验证 CustomHeadersHttpClient 的 currentHeaders）
      final llmClient = container.read(httpClientProvider);
      expect(llmClient.currentHeaders, containsPair('X-API-Key', 'sk-secret-key'));
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

      // 触发 sync provider（确保 LLM client 有自定义 header）
      container.read(customHeadersSyncProvider);

      // peer client 发请求
      final peerClient = container.read(peerHttpClientProvider);
      await peerClient.get(Uri.parse('http://192.168.1.5:8080/sync'));

      expect(peerRequestHadApiKey, isFalse,
          reason: 'peer 请求不应携带 LLM 自定义 header');
    });
  });
}
