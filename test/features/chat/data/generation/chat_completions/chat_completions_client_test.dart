import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

void main() {
  final testUri = Uri.parse('https://api.example.com/v1/chat/completions');

  ChatCompletionsClient buildChatClient(
    http.Client httpClient, {
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
    SseEventDecoder decoder = const SseEventDecoder(),
  }) {
    return ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: httpClient,
        logger: logger,
        extraHeadersFactory: extraHeadersFactory,
        decoder: decoder,
      ),
    );
  }

  http.StreamedResponse okResponse() {
    return http.StreamedResponse(
      Stream.fromIterable([
        utf8.encode('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'),
        utf8.encode('data: [DONE]\n\n'),
      ]),
      200,
    );
  }

  // ── 请求编码：外部协议契约 ───────────────────────────────────

  group('请求编码', () {
    test('客户端将原始 API 根解析为 Chat Completions 端点', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url, testUri);
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(apiUrl: 'https://api.example.com'),
            ),
          )
          .drain<void>();
    });

    test('无效原始 URL 在发 HTTP 前转换为 ChatGenerationException', () async {
      var sent = false;
      final client = _FakeStreamingHttpClient((request) async {
        sent = true;
        return okResponse();
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(
                _messages(),
                modelConfig: _modelConfig(apiUrl: 'not-a-url'),
              ),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having(
                (error) => error.protocol,
                'protocol',
                LlmApiProtocol.chatCompletions,
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
      expect(sent, isFalse);
    });

    test('Header 逐字：Content-Type/Accept/Authorization', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['Accept'], 'text/event-stream');
        expect(request.headers['Authorization'], 'Bearer sk-test-12345678');
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test('请求体逐字：model/stream/messages/reasoning_effort', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload, {
          'model': 'gpt-4.1',
          'stream': true,
          'messages': [
            {'role': 'system', 'content': '系统提示'},
            {'role': 'user', 'content': '你好'},
            {'role': 'assistant', 'content': '回复'},
          ],
          'reasoning_effort': 'medium',
        });
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(
            _request(
              const [
                ChatRequestMessage(
                  role: ChatMessageRole.system,
                  content: '系统提示',
                ),
                ChatRequestMessage(role: ChatMessageRole.user, content: '你好'),
                ChatRequestMessage(
                  role: ChatMessageRole.assistant,
                  content: '回复',
                ),
              ],
              modelConfig: _modelConfig(),
              reasoningEffort: ReasoningEffort.medium,
            ),
          )
          .drain<void>();
    });

    test('reasoningEffort 为 null 时不发送 reasoning_effort', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('reasoning_effort'), isFalse);
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test('全部 effort 值原样透传（low/medium/high/xhigh/max）', () async {
      const expectedEfforts = <ReasoningEffort, String>{
        ReasoningEffort.low: 'low',
        ReasoningEffort.medium: 'medium',
        ReasoningEffort.high: 'high',
        ReasoningEffort.xhigh: 'xhigh',
        ReasoningEffort.max: 'max',
      };

      for (final entry in expectedEfforts.entries) {
        String? sentEffort;
        final client = _FakeStreamingHttpClient((request) async {
          final payload = jsonDecode(
            (request as http.Request).body,
          ) as Map<String, dynamic>;
          sentEffort = payload['reasoning_effort'] as String?;
          return okResponse();
        });

        await buildChatClient(client)
            .streamCompletion(
              _request(
                _messages(),
                modelConfig: _modelConfig(),
                reasoningEffort: entry.key,
              ),
            )
            .drain<void>();

        expect(sentEffort, entry.value, reason: entry.key.name);
      }
    });

    test('DeepSeek 主机：无 thinking / extra_body 补丁', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload.containsKey('extra_body'), isFalse);
        expect(payload['reasoning_effort'], 'high');
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(
                apiUrl: 'https://api.deepseek.com/v1/chat/completions',
              ),
              reasoningEffort: ReasoningEffort.high,
            ),
          )
          .drain<void>();
    });

    test('Google 主机：无 extra_body，不跳过 reasoning_effort', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('extra_body'), isFalse);
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload['reasoning_effort'], 'medium');
        return okResponse();
      });

      await buildChatClient(client)
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(
                apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
              ),
              reasoningEffort: ReasoningEffort.medium,
            ),
          )
          .drain<void>();
    });

    test('请求日志合并自定义 header，反映最终实际请求头', () async {
      final logger = _FakeNetworkLogger();
      final client = _FakeStreamingHttpClient((_) async => okResponse());
      final chatClient = buildChatClient(
        client,
        logger: logger,
        extraHeadersFactory: () => const {'X-Custom-Header': 'custom-value'},
      );

      await chatClient
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();

      expect(logger.requestHeaders!['Content-Type'], 'application/json');
      expect(
        logger.requestHeaders!['Authorization'],
        'Bearer sk-test-12345678',
      );
      expect(logger.requestHeaders!['X-Custom-Header'], 'custom-value');
    });

    test('协议不匹配 → ChatGenerationException，且不发送请求', () async {
      final client = _FakeStreamingHttpClient((_) async {
        throw UnimplementedError('协议不匹配时不应发送请求');
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(
                _messages(),
                modelConfig: _modelConfig(
                  apiProtocol: LlmApiProtocol.anthropic,
                ),
              ),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.protocol,
            'protocol',
            LlmApiProtocol.anthropic,
          ),
        ),
      );
    });
  });

  // ── 行为等价（流式集成，经 transport + 假 http.Client）─────────

  group('行为等价', () {
    test('正文/推理流式产出 + finish_reason 透传 + [DONE] 正常结束', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}\n\n',
            ),
            utf8.encode('data: {"choices":[{"delta":{"content":"第一段 "}}]}\n\n'),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"第二段"},"finish_reason":"stop"}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });

      final chunks = await buildChatClient(client)
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(),
              reasoningEffort: ReasoningEffort.high,
            ),
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
      expect(chunks.last.finishReason, 'stop');
    });

    test('内联标签跨 chunk 经完整链路分流', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"A<think"}}]}\n\n',
            ),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"ing>隐藏</thinking>B"}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });

      final chunks = await buildChatClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .toList();

      expect(chunks.map((chunk) => chunk.contentDelta).join(), 'AB');
      expect(chunks.map((chunk) => chunk.reasoningDelta).join(), '隐藏');
    });

    test('非 2xx → ChatGenerationException 字段正确', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"bad key"}}')),
          401,
        );
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having(
                (e) => e.protocol,
                'protocol',
                LlmApiProtocol.chatCompletions,
              )
              .having((e) => e.uri, 'uri', testUri)
              .having(
                (e) => e.responseBody,
                'responseBody',
                '{"error":{"message":"bad key"}}',
              )
              .having((e) => e.message, 'message', contains('401')),
        ),
      );
    });

    test('连接异常 → ChatGenerationException（cause 与堆栈保留）', () async {
      final connectionError = http.ClientException(
        'connection refused',
        testUri,
      );
      final client = _FakeStreamingHttpClient((_) async {
        throw connectionError;
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.cause, 'cause', same(connectionError))
              .having((e) => e.causeStackTrace, 'causeStackTrace', isNotNull)
              .having(
                (e) => e.protocol,
                'protocol',
                LlmApiProtocol.chatCompletions,
              )
              .having((e) => e.uri, 'uri', testUri)
              .having(
                (e) => e.message,
                'message',
                contains('connection refused'),
              ),
        ),
      );
    });

    test('SSE 内 error → ChatGenerationException', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"error":{"message":"invalid api key"}}\n\n'),
          ]),
          200,
        );
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having(
                (e) => e.protocol,
                'protocol',
                LlmApiProtocol.chatCompletions,
              )
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('malformed JSON → ChatGenerationException', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode('data: {not valid json}\n\n')]),
          200,
        );
      });

      await expectLater(
        buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', contains('SSE 数据解析失败'))
              .having(
                (e) => e.protocol,
                'protocol',
                LlmApiProtocol.chatCompletions,
              )
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('空响应（无正文无推理）→ 无有效内容异常', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"model":"gpt-4.1"}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });

      try {
        await buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.message, contains('请求未返回有效内容'));
        expect(error.protocol, LlmApiProtocol.chatCompletions);
        expect(error.uri, testUri);
        expect(error.responseBody, contains('data: {"model":"gpt-4.1"}'));
      }
    });

    test('超长空响应 rawSseData 截尾：responseBody 只保留尾部 200 行', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < 250; i++)
              utf8.encode('data: {"model":"gpt-4.1","seq":$i}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });

      try {
        await buildChatClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.responseBody, isNotNull);
        expect(error.responseBody!.split('\n'), hasLength(200));
        expect(error.responseBody, endsWith('data: [DONE]'));
      }
    });

    test(
      'idle timeout → ChatGenerationException（cause 为 TimeoutException）',
      () async {
        final client = _FakeStreamingHttpClient((_) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode('data: x\n\n')),
            200,
          );
        });
        // 解码器计时语义由 decoder 层测试精确覆盖；这里注入立即超时的假
        // 解码器，确定性验证超时经 transport 转换后在客户端再次转换。
        final chatClient = buildChatClient(client, decoder: _TimeoutDecoder());

        await expectLater(
          chatClient
              .streamCompletion(
                _request(
                  _messages(),
                  modelConfig: _modelConfig(),
                  streamIdleTimeout: const Duration(seconds: 30),
                ),
              )
              .drain<void>(),
          throwsA(
            isA<ChatGenerationException>()
                .having((e) => e.cause, 'cause', isA<TimeoutException>())
                .having((e) => e.message, 'message', contains('超时')),
          ),
        );
      },
    );

    test('注释 keepalive 不重置 idle timeout（真实计时器）', () async {
      final source = StreamController<List<int>>();
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(source.stream, 200);
      });
      final chatClient = buildChatClient(client);

      final errors = <Object>[];
      // 以 Completer 等待超时错误，避免固定延时等待（仓库韧性门禁）。
      final errorArrived = Completer<void>();
      final subscription = chatClient
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(),
              streamIdleTimeout: const Duration(milliseconds: 100),
            ),
          )
          .listen(
            (_) {},
            onError: (Object error) {
              errors.add(error);
              if (!errorArrived.isCompleted) errorArrived.complete();
            },
            onDone: () {
              if (!errorArrived.isCompleted) errorArrived.complete();
            },
          );

      // 仅发送 SSE 注释行 keepalive：不重置 idle 计时器，超时应触发。
      source.add(utf8.encode(': keepalive\n\n'));
      await errorArrived.future.timeout(const Duration(seconds: 10));

      expect(errors, hasLength(1));
      expect(errors.single, isA<ChatGenerationException>());
      expect(
        (errors.single as ChatGenerationException).cause,
        isA<TimeoutException>(),
      );

      await subscription.cancel();
      await source.close();
    });

    test('complete() 折叠流式路径解析 message envelope', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"message":{"content":"完整回复","reasoning_content":"完整思考"},"finish_reason":"stop"}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });

      final result = await buildChatClient(client)
          .complete(_request(_messages(), modelConfig: _modelConfig()));

      expect(result.content, '完整回复');
      expect(result.reasoningContent, '完整思考');
      expect(result.finishReason, 'stop');
    });
  });
}

List<ChatRequestMessage> _messages() {
  return const [ChatRequestMessage(role: ChatMessageRole.user, content: '你好')];
}

LlmModelConfig _modelConfig({
  String apiUrl = 'https://api.example.com/v1/chat/completions',
  LlmApiProtocol apiProtocol = LlmApiProtocol.chatCompletions,
}) {
  return LlmModelConfig(
    id: 'model-1',
    displayName: 'GPT-4.1',
    apiUrl: apiUrl,
    apiKey: 'sk-test-12345678',
    modelName: 'gpt-4.1',
    supportsReasoning: true,
    apiProtocol: apiProtocol,
  );
}

ChatGenerationRequest _request(
  List<ChatRequestMessage> messages, {
  required LlmModelConfig modelConfig,
  ReasoningEffort? reasoningEffort,
  Duration? streamIdleTimeout,
}) {
  return ChatGenerationRequest(
    target: ChatGenerationRequestTarget(
      protocol: modelConfig.apiProtocol,
      endpoint: modelConfig.apiUrl.trim(),
      apiKey: modelConfig.apiKey,
      model: modelConfig.modelName,
    ),
    messages: messages,
    reasoningEffort: reasoningEffort,
    streamIdleTimeout: streamIdleTimeout,
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

/// 立即抛出超时错误的假解码器，用于确定性地验证客户端超时转换。
class _TimeoutDecoder extends SseEventDecoder {
  const _TimeoutDecoder();

  @override
  Stream<SseEvent> decode(
    Stream<List<int>> byteStream, {
    Duration? idleTimeout,
  }) {
    return Stream.error(TimeoutException('fake idle timeout'));
  }
}

final class _FakeNetworkLogger with NetworkLogger {
  Map<String, String>? requestHeaders;

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
    bool logBody = false,
  }) async {
    requestHeaders = headers;
  }
}
