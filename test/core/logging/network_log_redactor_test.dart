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

      expect(headers['Authorization'], '***');
      expect(headers['Content-Type'], 'application/json');
    });

    test('preserves non-sensitive headers', () {
      final headers = redactor.redactHeaders({
        'X-Custom-Header': 'visible-value',
      });

      expect(headers['X-Custom-Header'], 'visible-value');
    });

    test('handles empty headers map', () {
      expect(redactor.redactHeaders({}), isEmpty);
    });

    test('masks Cookie header', () {
      final headers = redactor.redactHeaders({'Cookie': 'session=abc123'});
      expect(headers['Cookie'], '***');
    });

    test('masks X-API-Key header', () {
      final headers = redactor.redactHeaders({'X-API-Key': 'sk-my-key'});
      expect(headers['X-API-Key'], '***');
    });

    test('masks Token / Access-Token / Auth-Token headers', () {
      final headers = redactor.redactHeaders({
        'Token': 'jwt.ey',
        'Access-Token': 'at-123',
        'Auth-Token': 'auth-456',
      });
      expect(headers['Token'], '***');
      expect(headers['Access-Token'], '***');
      expect(headers['Auth-Token'], '***');
    });

    test('masks Secret / Client-Secret headers', () {
      final headers = redactor.redactHeaders({
        'Secret': 'my-secret',
        'Client-Secret': 'cs-789',
      });
      expect(headers['Secret'], '***');
      expect(headers['Client-Secret'], '***');
    });

    test('masks Proxy-Authorization header (contains authorization)', () {
      final headers = redactor.redactHeaders({
        'Proxy-Authorization': 'Basic dXNlcjpwYXNz',
      });
      expect(headers['Proxy-Authorization'], '***');
    });

    test('masks case-insensitive header keys', () {
      final headers = redactor.redactHeaders({
        'AUTHORIZATION': 'Bearer x',
        'Cookie': 'y',
        'x-api-key': 'z',
      });
      expect(headers['AUTHORIZATION'], '***');
      expect(headers['Cookie'], '***');
      expect(headers['x-api-key'], '***');
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
              ])
              as List;

      expect((payload[0] as Map)['apiKey'], '***');
      expect((payload[1] as Map)['api_key'], '***');
    });

    test('masks token / secret / password / credential fields', () {
      final payload =
          redactor.redactPayload({
                'token': 'jwt-payload',
                'secret': 'my-secret',
                'password': 'hunter2',
                'credential': 'cred-123',
                'safe_value': 'keep-me',
              })
              as Map<String, Object?>;

      expect(payload['token'], '***');
      expect(payload['secret'], '***');
      expect(payload['password'], '***');
      expect(payload['credential'], '***');
      expect(payload['safe_value'], 'keep-me');
    });

    test('masks case-insensitive token/secret/password/credential', () {
      final payload =
          redactor.redactPayload({
                'Token': 't1',
                'SECRET': 's1',
                'Password': 'p1',
                'CREDENTIAL': 'c1',
              })
              as Map<String, Object?>;

      expect(payload['Token'], '***');
      expect(payload['SECRET'], '***');
      expect(payload['Password'], '***');
      expect(payload['CREDENTIAL'], '***');
    });

    test('masks nested token/secret/password fields', () {
      final payload =
          redactor.redactPayload({
                'config': {
                  'api': {'token': 'nested-token', 'name': 'keep'},
                },
              })
              as Map<String, Object?>;

      final config = payload['config']! as Map<String, Object?>;
      final api = config['api']! as Map<String, Object?>;
      expect(api['token'], '***');
      expect(api['name'], 'keep');
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
      final result = redactor.redactText('{"apiKey": "sk-visible-in-json"}');
      expect(result, '{"apiKey": "***"}');
    });
  });

  group('isSensitiveHeader', () {
    test('returns true for known sensitive headers', () {
      expect(redactor.isSensitiveHeader('Authorization'), isTrue);
      expect(redactor.isSensitiveHeader('Cookie'), isTrue);
      expect(redactor.isSensitiveHeader('X-API-Key'), isTrue);
      expect(redactor.isSensitiveHeader('Token'), isTrue);
      expect(redactor.isSensitiveHeader('Access-Token'), isTrue);
      expect(redactor.isSensitiveHeader('Auth-Token'), isTrue);
      expect(redactor.isSensitiveHeader('Secret'), isTrue);
      expect(redactor.isSensitiveHeader('Client-Secret'), isTrue);
      expect(redactor.isSensitiveHeader('Proxy-Authorization'), isTrue);
    });

    test('returns false for non-sensitive headers', () {
      expect(redactor.isSensitiveHeader('Content-Type'), isFalse);
      expect(redactor.isSensitiveHeader('Accept'), isFalse);
      expect(redactor.isSensitiveHeader('X-Custom'), isFalse);
      expect(redactor.isSensitiveHeader('User-Agent'), isFalse);
    });

    test('is case-insensitive', () {
      expect(redactor.isSensitiveHeader('authorization'), isTrue);
      expect(redactor.isSensitiveHeader('COOKIE'), isTrue);
      expect(redactor.isSensitiveHeader('x-api-key'), isTrue);
    });
  });
}
