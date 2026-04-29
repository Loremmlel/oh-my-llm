import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/network_log_redactor.dart';

void main() {
  test('redactHeaders masks Authorization bearer token', () {
    const redactor = NetworkLogRedactor();
    final headers = redactor.redactHeaders({
      'Authorization': 'Bearer sk-test-123456',
      'Content-Type': 'application/json',
    });

    expect(headers['Authorization'], 'Bearer ***');
    expect(headers['Content-Type'], 'application/json');
  });

  test('redactPayload masks apiKey fields recursively', () {
    const redactor = NetworkLogRedactor();
    final payload =
        redactor.redactPayload({
              'apiKey': 'sk-top-level',
              'nested': {'api_key': 'sk-nested', 'value': 'ok'},
            })
            as Map<String, Object?>;

    expect(payload['apiKey'], '***');
    final nested = payload['nested']! as Map<String, Object?>;
    expect(nested['api_key'], '***');
    expect(nested['value'], 'ok');
  });
}
