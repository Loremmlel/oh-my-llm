import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
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

    // 解析与失败行为与协议无关（代码路径仅在认证 Header 处分叉），
    // 三种协议共用同一组测试。
    for (final protocol in LlmApiProtocol.values) {
      group('$protocol', () {
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
            apiProtocol: protocol,
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
            apiProtocol: protocol,
          );

          expect(result, isEmpty);
        });

        test(
          'fetchModels returns empty list when data field is missing',
          () async {
            final mockClient = MockClient((request) async {
              return http.Response(jsonEncode({'object': 'list'}), 200);
            });
            client = createClient(mockClient);

            final result = await client.fetchModels(
              modelsUrl: 'https://api.openai.com/v1/models',
              apiKey: 'sk-test',
              apiProtocol: protocol,
            );

            expect(result, isEmpty);
          },
        );

        test('fetchModels throws ModelListException on HTTP error', () async {
          final mockClient = MockClient((request) async {
            return http.Response('{"error": "unauthorized"}', 401);
          });
          client = createClient(mockClient);

          expect(
            () => client.fetchModels(
              modelsUrl: 'https://api.openai.com/v1/models',
              apiKey: 'bad-key',
              apiProtocol: protocol,
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
              apiProtocol: protocol,
            ),
            throwsA(
              isA<ModelListException>().having(
                (e) => e.message,
                'message',
                contains('解析失败'),
              ),
            ),
          );
        });

        test(
          'fetchModels throws ModelListException on network error',
          () async {
            final mockClient = MockClient((request) async {
              throw http.ClientException('连接失败');
            });
            client = createClient(mockClient);

            expect(
              () => client.fetchModels(
                modelsUrl: 'https://api.openai.com/v1/models',
                apiKey: 'sk-test',
                apiProtocol: protocol,
              ),
              throwsA(
                isA<ModelListException>().having(
                  (e) => e.message,
                  'message',
                  contains('网络请求失败'),
                ),
              ),
            );
          },
        );

        test('fetchModels throws ModelListException for invalid URL', () async {
          final mockClient = MockClient((request) async {
            return http.Response(modelsResponseJson(['gpt-4o']), 200);
          });
          client = createClient(mockClient);

          expect(
            () => client.fetchModels(
              modelsUrl: 'not a url',
              apiKey: 'sk-test',
              apiProtocol: protocol,
            ),
            throwsA(
              isA<ModelListException>().having(
                (e) => e.message,
                'message',
                contains('URL 格式无效'),
              ),
            ),
          );
        });

        test(
          'fetchModels truncates long error response body in exception',
          () async {
            final longBody = 'x' * 500;
            final mockClient = MockClient((request) async {
              return http.Response(longBody, 500);
            });
            client = createClient(mockClient);

            try {
              await client.fetchModels(
                modelsUrl: 'https://api.openai.com/v1/models',
                apiKey: 'sk-test',
                apiProtocol: protocol,
              );
              fail('Should have thrown');
            } on ModelListException catch (e) {
              expect(e.responseBody, isNotNull);
              // truncateJsonValues 截断到 200 字符后追加 ...[truncated]
              expect(e.responseBody!.length, lessThanOrEqualTo(220));
              expect(e.responseBody, contains('...'));
            }
          },
        );
      });
    }

    group('auth headers by protocol', () {
      for (final protocol in [
        LlmApiProtocol.chatCompletions,
        LlmApiProtocol.responses,
      ]) {
        test('$protocol sends Authorization Bearer header', () async {
          Map<String, String>? capturedHeaders;
          final mockClient = MockClient((request) async {
            capturedHeaders = request.headers;
            return http.Response(modelsResponseJson(['gpt-4o']), 200);
          });
          client = createClient(mockClient);

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

      test('anthropic sends x-api-key and anthropic-version headers', () async {
        Map<String, String>? capturedHeaders;
        final mockClient = MockClient((request) async {
          capturedHeaders = request.headers;
          return http.Response(modelsResponseJson(['claude-3-5-sonnet']), 200);
        });
        client = createClient(mockClient);

        await client.fetchModels(
          modelsUrl: 'https://api.anthropic.com/v1/models',
          apiKey: 'sk-ant-my-key',
          apiProtocol: LlmApiProtocol.anthropic,
        );

        expect(capturedHeaders?['x-api-key'], 'sk-ant-my-key');
        expect(capturedHeaders?['anthropic-version'], '2023-06-01');
        expect(capturedHeaders?['Accept'], 'application/json');
        // Anthropic 不用 Bearer，避免与 x-api-key 双认证混淆。
        expect(capturedHeaders?['Authorization'], isNull);
      });

      test('自定义 Header 覆盖认证默认值后 wire 与请求日志一致', () async {
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
        client = ModelListClient(
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
