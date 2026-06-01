import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/network_log_redactor.dart';

void main() {
  const redactor = NetworkLogRedactor();

  group('redactHeaders', () {
    test('masks Authorization bearer token (case-insensitive key)', () {
      final headers = redactor.redactHeaders({
        'Authorization': 'Bearer sk-test-123456',
        'Content-Type': 'application/json',
      });

      expect(headers['Authorization'], 'Bearer ***');
      expect(headers['Content-Type'], 'application/json');
    });

    test('preserves non-Authorization headers', () {
      final headers = redactor.redactHeaders({
        'X-Custom-Header': 'visible-value',
      });

      expect(headers['X-Custom-Header'], 'visible-value');
    });

    test('handles empty headers map', () {
      expect(redactor.redactHeaders({}), isEmpty);
    });
  });

  group('redactPayload', () {
    test('masks apiKey / api_key fields recursively', () {
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

    test('masks case-insensitive api key field variants', () {
      final payload =
          redactor.redactPayload({
                'API_KEY': 'sk-upper',
                'ApiKey': 'sk-mixed',
                'safe_field': 'keep-me',
              })
              as Map<String, Object?>;

      expect(payload['API_KEY'], '***');
      expect(payload['ApiKey'], '***');
      expect(payload['safe_field'], 'keep-me');
    });

    test('handles null and non-map payloads', () {
      expect(redactor.redactPayload(null), isNull);
      expect(redactor.redactPayload(42), 42);
      expect(redactor.redactPayload('hello'), 'hello');
    });

    test('masks values in list payloads', () {
      final payload =
          redactor.redactPayload([
                {'apiKey': 'secret1'},
                {'api_key': 'secret2'},
              ]) as List;

      expect((payload[0] as Map)['apiKey'], '***');
      expect((payload[1] as Map)['api_key'], '***');
    });
  });

  group('redactText', () {
    test('masks Bearer tokens inline', () {
      final result = redactor.redactText(
        'Authorization: Bearer sk-test-token-abc123',
      );
      expect(result, 'Authorization: Bearer ***');
    });

    test('masks JSON api key fields in text', () {
      final result = redactor.redactText(
        '{"apiKey": "sk-visible-in-json"}',
      );
      expect(result, '{"apiKey": "***"}');
    });
  });
}
