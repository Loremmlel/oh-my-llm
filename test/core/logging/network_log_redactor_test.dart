import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/logging/network_log_redactor.dart';

void main() {
  const redactor = NetworkLogRedactor();

  group('redactHeaders', () {
    test('遮罩全部已知敏感类别并保留普通 header', () {
      const sensitiveKeys = [
        'Authorization',
        'Cookie',
        'X-API-Key',
        'Token',
        'Access-Token',
        'Auth-Token',
        'Secret',
        'Client-Secret',
        'Proxy-Authorization',
      ];
      final headers = redactor.redactHeaders({
        for (final key in sensitiveKeys) key: 'sensitive-value',
        'Content-Type': 'application/json',
        'X-Custom-Header': 'visible-value',
      });

      for (final key in sensitiveKeys) {
        expect(headers[key], '***', reason: '$key 必须脱敏');
      }
      expect(headers['Content-Type'], 'application/json');
      expect(headers['X-Custom-Header'], 'visible-value');
    });

    test('敏感 header 匹配不区分大小写', () {
      final headers = redactor.redactHeaders({
        'AUTHORIZATION': 'Bearer x',
        'cookie': 'y',
        'x-api-key': 'z',
      });

      expect(headers.values, everyElement('***'));
    });
  });

  group('redactPayload', () {
    test('递归遮罩 Map 与 List 中全部已知敏感字段', () {
      final payload =
          redactor.redactPayload({
                'apiKey': 'sk-top-level',
                'api_key': 'sk-snake-case',
                'Token': 'case-insensitive-token',
                'SECRET': 'case-insensitive-secret',
                'Password': 'case-insensitive-password',
                'CREDENTIAL': 'case-insensitive-credential',
                'safe_value': 'keep-me',
                'nested': {'token': 'nested-token', 'name': 'keep-nested'},
                'items': [
                  {'secret': 'list-secret'},
                ],
              })
              as Map<String, Object?>;

      for (final key in [
        'apiKey',
        'api_key',
        'Token',
        'SECRET',
        'Password',
        'CREDENTIAL',
      ]) {
        expect(payload[key], '***', reason: '$key 必须脱敏');
      }
      expect(payload['safe_value'], 'keep-me');

      final nested = payload['nested']! as Map<String, Object?>;
      expect(nested['token'], '***');
      expect(nested['name'], 'keep-nested');

      final items = payload['items']! as List<Object?>;
      expect((items.single! as Map)['secret'], '***');
    });

    test('null 与普通标量保持原值', () {
      for (final value in <Object?>[null, 42, true, 'hello']) {
        expect(redactor.redactPayload(value), value);
      }
    });
  });

  group('redactText', () {
    test('遮罩内联 Bearer token', () {
      expect(
        redactor.redactText('Authorization: Bearer sk-test-token-abc123'),
        'Authorization: Bearer ***',
      );
    });

    test('遮罩文本中的 JSON API key 字段', () {
      expect(
        redactor.redactText('{"apiKey": "sk-visible-in-json"}'),
        '{"apiKey": "***"}',
      );
    });
  });
}
