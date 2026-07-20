import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/features/settings/data/model_list_client.dart';

void main() {
  group('ModelListClient', () {
    late ModelListClient client;

    ModelListClient createClient(http.Client httpClient) {
      return ModelListClient(httpClient: httpClient);
    }

    String modelsResponseJson(List<String> modelIds) {
      return jsonEncode({
        'object': 'list',
        'data': modelIds
            .map((id) => {
                  'id': id,
                  'object': 'model',
                  'created': 1715367049,
                  'owned_by': 'openai',
                })
            .toList(),
      });
    }

    test('fetchModels returns parsed model list', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          modelsResponseJson(['gpt-4o', 'gpt-4o-mini']),
          200,
        );
      });
      client = createClient(mockClient);

      final result = await client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'sk-test',
      );

      expect(result.length, 2);
      expect(result[0].id, 'gpt-4o');
      expect(result[0].ownedBy, 'openai');
      expect(result[1].id, 'gpt-4o-mini');
    });

    test('fetchModels returns empty list when data is empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'object': 'list', 'data': []}),
          200,
        );
      });
      client = createClient(mockClient);

      final result = await client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'sk-test',
      );

      expect(result, isEmpty);
    });

    test('fetchModels returns empty list when data field is missing', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'object': 'list'}),
          200,
        );
      });
      client = createClient(mockClient);

      final result = await client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'sk-test',
      );

      expect(result, isEmpty);
    });

    test('fetchModels sends Authorization header', () async {
      String? capturedAuthHeader;
      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response(modelsResponseJson(['gpt-4o']), 200);
      });
      client = createClient(mockClient);

      await client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'sk-my-key',
      );

      expect(capturedAuthHeader, 'Bearer sk-my-key');
    });

    test('fetchModels throws ModelListException on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error": "unauthorized"}', 401);
      });
      client = createClient(mockClient);

      expect(
        () => client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'bad-key',
        ),
        throwsA(
          isA<ModelListException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('401')),
        ),
      );
    });

    test('fetchModels throws ModelListException on invalid JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not json at all', 200);
      });
      client = createClient(mockClient);

      expect(
        () => client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'sk-test',
        ),
        throwsA(
          isA<ModelListException>()
              .having((e) => e.message, 'message', contains('解析失败')),
        ),
      );
    });

    test('fetchModels throws ModelListException on network error', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('连接失败');
      });
      client = createClient(mockClient);

      expect(
        () => client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'sk-test',
        ),
        throwsA(
          isA<ModelListException>()
              .having((e) => e.message, 'message', contains('网络请求失败')),
        ),
      );
    });

    test('fetchModels throws ModelListException for invalid URL', () async {
      final mockClient = MockClient((request) async {
        return http.Response(modelsResponseJson(['gpt-4o']), 200);
      });
      client = createClient(mockClient);

      expect(
        () => client.fetchModels(
          modelsUrl: 'not a url',
          apiKey: 'sk-test',
        ),
        throwsA(
          isA<ModelListException>()
              .having((e) => e.message, 'message', contains('URL 格式无效')),
        ),
      );
    });

    test('fetchModels truncates long error response body in exception', () async {
      final longBody = 'x' * 500;
      final mockClient = MockClient((request) async {
        return http.Response(longBody, 500);
      });
      client = createClient(mockClient);

      try {
        await client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'sk-test',
        );
        fail('Should have thrown');
      } on ModelListException catch (e) {
        expect(e.responseBody, isNotNull);
        expect(e.responseBody!.length, lessThanOrEqualTo(203));
        expect(e.responseBody, contains('...'));
      }
    });
  });
}
