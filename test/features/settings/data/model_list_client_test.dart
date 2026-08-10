import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/features/settings/data/model_list_client.dart';
import 'package:oh_my_llm/features/settings/domain/models/model_catalog_entry.dart';

void main() {
  group('ModelListClient', () {
    String modelsResponseJson(List<String> modelIds) {
      return jsonEncode({
        'object': 'list',
        'data': modelIds
            .map(
              (id) => {
                'id': id,
                'object': 'model',
                'created': 1715367049,
                'owned_by': 'openai',
              },
            )
            .toList(),
      });
    }

    Future<List<ModelCatalogEntry>> fetchWithResponse(
      String body, {
      int status = 200,
    }) {
      final client = ModelListClient(
        httpClient: MockClient((_) async => http.Response(body, status)),
      );
      return client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'sk-test',
        apiProtocol: LlmApiProtocol.chatCompletions,
      );
    }

    test('fetchModels returns the parsed model list', () async {
      final result = await fetchWithResponse(
        modelsResponseJson(['gpt-4o', 'gpt-4o-mini']),
      );

      expect(result, hasLength(2));
      expect(result[0].id, 'gpt-4o');
      expect(result[0].ownedBy, 'openai');
      expect(result[1].id, 'gpt-4o-mini');
    });

    test('fetchModels returns empty when data is an empty list', () async {
      expect(
        await fetchWithResponse(jsonEncode({'object': 'list', 'data': []})),
        isEmpty,
      );
    });

    test('fetchModels returns empty when the data field is missing', () async {
      expect(await fetchWithResponse(jsonEncode({'object': 'list'})), isEmpty);
    });

    test('fetchModels reports HTTP status and body on an error', () async {
      await expectLater(
        fetchWithResponse('{"error":"unauthorized"}', status: 401),
        throwsA(
          isA<ModelListException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.message, 'message', contains('401'))
              .having(
                (error) => error.responseBody,
                'responseBody',
                contains('unauthorized'),
              ),
        ),
      );
    });

    test('fetchModels reports invalid JSON as a parsing failure', () async {
      await expectLater(
        fetchWithResponse('not json at all'),
        throwsA(
          isA<ModelListException>().having(
            (error) => error.message,
            'message',
            contains('解析失败'),
          ),
        ),
      );
    });

    test('fetchModels maps client exceptions to network failures', () async {
      final client = ModelListClient(
        httpClient: MockClient((_) async {
          throw http.ClientException('连接失败');
        }),
      );

      await expectLater(
        client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'sk-test',
          apiProtocol: LlmApiProtocol.chatCompletions,
        ),
        throwsA(
          isA<ModelListException>().having(
            (error) => error.message,
            'message',
            contains('网络请求失败'),
          ),
        ),
      );
    });

    test('fetchModels rejects a URL without an HTTP scheme', () async {
      final client = ModelListClient(
        httpClient: MockClient(
          (_) async => http.Response(modelsResponseJson(['gpt-4o']), 200),
        ),
      );

      await expectLater(
        client.fetchModels(
          modelsUrl: 'not a url',
          apiKey: 'sk-test',
          apiProtocol: LlmApiProtocol.chatCompletions,
        ),
        throwsA(
          isA<ModelListException>().having(
            (error) => error.message,
            'message',
            contains('URL 格式无效'),
          ),
        ),
      );
    });

    test('fetchModels truncates a long error response body', () async {
      await expectLater(
        fetchWithResponse('x' * 500, status: 500),
        throwsA(
          isA<ModelListException>()
              .having(
                (error) => error.responseBody?.length,
                'truncated length',
                lessThanOrEqualTo(220),
              )
              .having(
                (error) => error.responseBody,
                'ellipsis',
                contains('...'),
              ),
        ),
      );
    });

    for (final protocol in [
      LlmApiProtocol.chatCompletions,
      LlmApiProtocol.responses,
    ]) {
      test('$protocol sends Bearer authentication', () async {
        Map<String, String>? capturedHeaders;
        final client = ModelListClient(
          httpClient: MockClient((request) async {
            capturedHeaders = request.headers;
            return http.Response(modelsResponseJson(['gpt-4o']), 200);
          }),
        );

        await client.fetchModels(
          modelsUrl: 'https://api.openai.com/v1/models',
          apiKey: 'sk-my-key',
          apiProtocol: protocol,
        );

        expect(capturedHeaders?['Authorization'], 'Bearer sk-my-key');
        expect(capturedHeaders?['Accept'], 'application/json');
        expect(capturedHeaders?['x-api-key'], isNull);
      });
    }

    test('Anthropic sends x-api-key and version authentication', () async {
      Map<String, String>? capturedHeaders;
      final client = ModelListClient(
        httpClient: MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(modelsResponseJson(['claude-3-5-sonnet']), 200);
        }),
      );

      await client.fetchModels(
        modelsUrl: 'https://api.anthropic.com/v1/models',
        apiKey: 'sk-ant-my-key',
        apiProtocol: LlmApiProtocol.anthropic,
      );

      expect(capturedHeaders?['x-api-key'], 'sk-ant-my-key');
      expect(capturedHeaders?['anthropic-version'], '2023-06-01');
      expect(capturedHeaders?['Accept'], 'application/json');
      expect(capturedHeaders?['Authorization'], isNull);
    });

    test('custom Headers override defaults on the wire and in logs', () async {
      const customHeaders = {
        'authorization': 'Bearer user-override',
        'X-Tenant': 'tenant-a',
      };
      Map<String, String>? wireHeaders;
      final inner = MockClient((request) async {
        wireHeaders = request.headers;
        return http.Response(modelsResponseJson(['gpt-4o']), 200);
      });
      final logger = _CapturingNetworkLogger();
      final client = ModelListClient(
        httpClient: CustomHeadersHttpClient(inner, customHeaders),
        logger: logger,
        extraHeadersFactory: () => customHeaders,
      );

      await client.fetchModels(
        modelsUrl: 'https://api.openai.com/v1/models',
        apiKey: 'default-key',
        apiProtocol: LlmApiProtocol.responses,
      );

      expect(
        _headerValue(wireHeaders!, 'authorization'),
        'Bearer user-override',
      );
      expect(
        _headerValue(logger.requestHeaders!, 'authorization'),
        'Bearer user-override',
      );
      expect(_headerValue(logger.requestHeaders!, 'x-tenant'), 'tenant-a');
    });
  });
}

String? _headerValue(Map<String, String> headers, String name) {
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) return entry.value;
  }
  return null;
}

final class _CapturingNetworkLogger with NetworkLogger {
  Map<String, String>? requestHeaders;

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
    bool logBody = false,
  }) async {
    requestHeaders = Map<String, String>.from(headers);
  }
}
