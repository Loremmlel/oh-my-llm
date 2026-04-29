import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  test('streamCompletion parses OpenAI-compatible SSE chunks', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer sk-test-12345678');
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload['reasoning_effort'], 'high');

        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}\n\n',
            ),
            utf8.encode('data: {"choices":[{"delta":{"content":"第一段 "}}]}\n\n'),
            utf8.encode('data: {"choices":[{"delta":{"content":"第二段"}}]}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
          reasoningEffort: ReasoningEffort.high,
        )
        .toList();

    expect(chunks.map((chunk) => chunk.reasoningDelta).toList(), [
      '思考中',
      '',
      '',
    ]);
    expect(chunks.map((chunk) => chunk.contentDelta).toList(), [
      '',
      '第一段 ',
      '第二段',
    ]);
  });

  test('streamCompletion writes request and response logs', () async {
    final logger = _FakeNetworkLogger();
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
      logger: logger,
    );

    await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: 'hello',
            ),
          ],
        )
        .drain<void>();

    expect(logger.requestCount, 1);
    expect(logger.responseCount, 1);
    expect(logger.sseCount, greaterThan(0));
  });

  test(
    'streamCompletion explicitly disables thinking when reasoning is off',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          expect(payload.containsKey('thinking'), isFalse);
          expect(payload.containsKey('reasoning_effort'), isFalse);

          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>();
    },
  );

  test('streamCompletion omits thinking for official OpenAI hosts', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload['reasoning_effort'], 'xhigh');

        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
          200,
        );
      }),
    );

    await client
        .streamCompletion(
          modelConfig: _modelConfig(
            apiUrl: 'https://api.openai.com/v1/chat/completions',
          ),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
          reasoningEffort: ReasoningEffort.xhigh,
        )
        .drain<void>();
  });

  test('streamCompletion surfaces API errors from SSE payloads', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"error":{"message":"invalid api key"}}\n\n'),
          ]),
          200,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(
        isA<ChatCompletionException>().having(
          (error) => error.message,
          'message',
          'invalid api key',
        ),
      ),
    );
  });

  test('streamCompletion rejects invalid API URLs before sending', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        throw UnimplementedError('Should not send request for invalid URLs.');
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(apiUrl: 'not-a-valid-url'),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(isA<ChatCompletionException>()),
    );
  });

  test('streamCompletion throws on HTTP 4xx status codes', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('Unauthorized')]),
          401,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(
        isA<ChatCompletionException>().having(
          (e) => e.message,
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('streamCompletion throws on HTTP 5xx status codes', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('Internal Server Error')]),
          500,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(
        isA<ChatCompletionException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('streamCompletion ignores non-data SSE lines', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            // event: 和 id: 行应被忽略，不影响解析。
            utf8.encode('event: message\n'),
            utf8.encode('id: 1\n'),
            utf8.encode('data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
        )
        .toList();

    expect(chunks.map((c) => c.contentDelta).toList(), ['hi']);
  });

  test('streamCompletion handles malformed JSON with exception', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: {not valid json}\n\n')]),
          200,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(isA<ChatCompletionException>()),
    );
  });

  test(
    'streamCompletion handles non-Map JSON gracefully (returns empty chunk)',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode('data: [1, 2, 3]\n\n'),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .toList();

      // 非 Map JSON 返回空 chunk，不抛出异常。
      expect(chunks, hasLength(1));
      expect(chunks.single.isEmpty, isTrue);
    },
  );

  test('streamCompletion handles missing choices field', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"model":"gpt-4"}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
        )
        .toList();

    expect(chunks.single.isEmpty, isTrue);
  });

  test('streamCompletion parses string-type error in SSE payload', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"error":"rate limit exceeded"}\n\n'),
          ]),
          200,
        );
      }),
    );

    expect(
      client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .drain<void>(),
      throwsA(
        isA<ChatCompletionException>().having(
          (e) => e.message,
          'message',
          'rate limit exceeded',
        ),
      ),
    );
  });

  test(
    'streamCompletion ReasoningEffort.low maps to "high" on compatible host',
    () async {
      String? sentEffort;
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.low,
          )
          .drain<void>();

      expect(sentEffort, 'low');
    },
  );

  test(
    'streamCompletion ReasoningEffort.medium maps to "high" on compatible host',
    () async {
      String? sentEffort;
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.medium,
          )
          .drain<void>();

      expect(sentEffort, 'medium');
    },
  );

  test(
    'streamCompletion ReasoningEffort.xhigh maps to "max" on compatible host',
    () async {
      String? sentEffort;
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.xhigh,
          )
          .drain<void>();

      expect(sentEffort, 'xhigh');
    },
  );

  test(
    'streamCompletion sends native effort values for official OpenAI subdomains',
    () async {
      // *.openai.com 子域名也应视为官方主机。
      String? sentEffort;
      bool? hasThinking;
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          hasThinking = payload.containsKey('thinking');
          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(
              apiUrl: 'https://api.openai.com/v1/chat/completions',
            ),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.low,
          )
          .drain<void>();

      // 官方 OpenAI 主机不发 thinking 字段，effort 直接用原生值。
      expect(hasThinking, isFalse);
      expect(sentEffort, 'low');
    },
  );

  test('streamCompletion extracts text from array content payload', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":[{"text":"segment1"},{"text":"segment2"}]}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
        )
        .toList();

    expect(chunks.single.contentDelta, 'segment1segment2');
  });

  test(
    'streamCompletion extracts Gemini thought summaries from content parts',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":[{"text":"最终答案"},{"text":"思考摘要","thought":true}]}}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.high,
          )
          .toList();

      expect(chunks.map((c) => c.contentDelta).join(), '最终答案');
      expect(chunks.map((c) => c.reasoningDelta).join(), '思考摘要');
    },
  );

  test(
    'streamCompletion keeps rolling thought summaries in streaming chunks',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":[{"text":"阶段一总结","thought":true}]}}]}\n\n',
              ),
              utf8.encode(
                'data: {"choices":[{"delta":{"content":[{"text":"阶段二总结","thought":true}]}}]}\n\n',
              ),
              utf8.encode(
                'data: {"choices":[{"delta":{"content":[{"text":"正文补充"}]}}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.high,
          )
          .toList();

      expect(chunks.map((c) => c.reasoningDelta).join(), '阶段一总结阶段二总结');
      expect(chunks.map((c) => c.contentDelta).join(), '正文补充');
    },
  );

  test(
    'streamCompletion extracts reasoning from "reasoning" alias field',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"reasoning":"别名推理内容"}}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.high,
          )
          .toList();

      expect(chunks.map((c) => c.reasoningDelta).toList(), ['别名推理内容']);
    },
  );

  test(
    'streamCompletion moves <thinking> content from body into reasoning',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"回答前缀<thinking>隐藏推理</thinking>回答后缀"}}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .toList();

      expect(chunks.map((c) => c.contentDelta).join(), '回答前缀回答后缀');
      expect(chunks.map((c) => c.reasoningDelta).join(), '隐藏推理');
    },
  );

  test('streamCompletion supports thoughts/thinkings tag variants', () async {
    final client = OpenAiCompatibleChatClient(
      httpClient: _FakeStreamingHttpClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"A<THOUGHTS>R1</THOUGHTS>B<thinkings>R2</thinkings>C"}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      }),
    );

    final chunks = await client
        .streamCompletion(
          modelConfig: _modelConfig(),
          messages: const [
            ChatCompletionRequestMessage(
              role: ChatMessageRole.user,
              content: '你好',
            ),
          ],
        )
        .toList();

    expect(chunks.map((c) => c.contentDelta).join(), 'ABC');
    expect(chunks.map((c) => c.reasoningDelta).join(), 'R1R2');
  });

  test(
    'streamCompletion extracts inline reasoning across chunk boundaries',
    () async {
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"A<think"}}]}\n\n',
              ),
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"ing>R"}}]}\n\n',
              ),
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"1</thinking>B"}}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
          );
        }),
      );

      final chunks = await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
          )
          .toList();

      expect(chunks.map((c) => c.contentDelta).join(), 'AB');
      expect(chunks.map((c) => c.reasoningDelta).join(), 'R1');
    },
  );

  test(
    'streamCompletion sends ReasoningEffort.high as "high" on compatible host',
    () async {
      String? sentEffort;
      final client = OpenAiCompatibleChatClient(
        httpClient: _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('data: [DONE]\n\n')]),
            200,
          );
        }),
      );

      await client
          .streamCompletion(
            modelConfig: _modelConfig(),
            messages: const [
              ChatCompletionRequestMessage(
                role: ChatMessageRole.user,
                content: '你好',
              ),
            ],
            reasoningEffort: ReasoningEffort.high,
          )
          .drain<void>();

      expect(sentEffort, 'high');
    },
  );
}

LlmModelConfig _modelConfig({
  String apiUrl = 'https://api.example.com/v1/chat/completions',
}) {
  return LlmModelConfig(
    id: 'model-1',
    displayName: 'GPT-4.1',
    apiUrl: apiUrl,
    apiKey: 'sk-test-12345678',
    modelName: 'gpt-4.1',
    supportsReasoning: true,
  );
}

class _FakeStreamingHttpClient extends http.BaseClient {
  _FakeStreamingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

final class _FakeNetworkLogger implements NetworkLogger {
  int requestCount = 0;
  int responseCount = 0;
  int sseCount = 0;

  @override
  Future<void> onAppLaunch() async {}

  @override
  Future<void> onAppDetached() async {}

  @override
  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {}

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  }) async {
    requestCount += 1;
  }

  @override
  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {
    responseCount += 1;
  }

  @override
  Future<void> logSseLine({required Uri uri, required String line}) async {
    sseCount += 1;
  }
}
