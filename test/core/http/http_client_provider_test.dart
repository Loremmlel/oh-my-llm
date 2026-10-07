import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';

void main() {
  test('生产 HTTP 绑定只向 LLM 请求注入自定义 Header，peer 请求保持隔离', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String, Map<String, String?>>{};
    const headers = {
      'Authorization': 'Bearer test-secret',
      'Cookie': 'session=test-secret',
      'X-API-Key': 'test-secret',
      'X-Custom': 'custom-value',
    };
    final subscription = server.listen((request) async {
      received[request.uri.path] = {
        for (final name in headers.keys) name: request.headers.value(name),
      };
      request.response.write('{}');
      await request.response.close();
    });
    addTearDown(subscription.cancel);

    final container = ProviderContainer(
      overrides: [customHeadersMapProvider.overrideWith((ref) => headers)],
    );
    addTearDown(container.dispose);
    container.read(customHeadersSyncProvider);
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}');

    await container.read(httpClientProvider).get(endpoint.resolve('/llm'));
    await container.read(peerHttpClientProvider).get(endpoint.resolve('/peer'));

    expect(received.keys, unorderedEquals(['/llm', '/peer']));
    expect(received['/llm'], headers);
    expect(received['/peer'], {for (final name in headers.keys) name: null});
  });
}
