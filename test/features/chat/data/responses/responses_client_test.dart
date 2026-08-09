import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  final testUri = Uri.parse('https://api.example.com/v1/responses');

  ResponsesClient buildResponsesClient(
    http.Client httpClient, {
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
    SseEventDecoder decoder = const SseEventDecoder(),
  }) {
    return ResponsesClient(
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
        utf8.encode(
          'data: {"type":"response.output_text.delta","delta":"ok"}\n\n',
        ),
        utf8.encode('data: {"type":"response.completed"}\n\n'),
        utf8.encode(
          'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
        ),
      ]),
      200,
    );
  }

  // ── 请求编码：外部协议契约 ───────────────────────────────────

  group('请求编码', () {
    test('客户端将原始 API 根解析为 Responses 端点', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url, testUri);
        return okResponse();
      });

      await buildResponsesClient(client)
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
        buildResponsesClient(client)
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
                LlmApiProtocol.responses,
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
      expect(sent, isFalse);
    });

    test('response.completed 后即使 HTTP 流保持打开也立即结束', () async {
      final cancelled = Completer<void>();
      late final StreamController<List<int>> responseController;
      responseController = StreamController<List<int>>(
        onListen: () {
          responseController.add(
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"ok"}\n\n',
            ),
          );
          responseController.add(
            utf8.encode(
              'data: {"type":"response.completed","response":{}}\n\n',
            ),
          );
        },
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      final httpClient = _FakeStreamingHttpClient(
        (_) async => http.StreamedResponse(responseController.stream, 200),
      );

      final chunks = await buildResponsesClient(httpClient)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .toList()
          .timeout(const Duration(seconds: 1));

      expect(chunks.map((chunk) => chunk.contentDelta).join(), 'ok');
      expect(chunks.last.finishReason, 'stop');
      await cancelled.future.timeout(const Duration(seconds: 1));
    });

    test('Header 逐字：Content-Type/Accept/Authorization', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['Accept'], 'text/event-stream');
        expect(request.headers['Authorization'], 'Bearer sk-test-12345678');
        return okResponse();
      });

      await buildResponsesClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test('请求体逐字：model/stream/store:false/input/reasoning 三字段', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload, {
          'model': 'gpt-5',
          'stream': true,
          'store': false,
          'input': [
            {'role': 'system', 'content': '系统提示'},
            {'role': 'user', 'content': '你好'},
            {'role': 'assistant', 'content': '回复'},
          ],
          'reasoning': {
            'effort': 'medium',
            'summary': 'auto',
            'context': 'current_turn',
          },
        });
        return okResponse();
      });

      await buildResponsesClient(client)
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

    test(
      '不含 previous_response_id / conversation / encrypted include',
      () async {
        final client = _FakeStreamingHttpClient((request) async {
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          expect(payload.containsKey('previous_response_id'), isFalse);
          expect(payload.containsKey('conversation'), isFalse);
          final reasoning = payload['reasoning'];
          expect(reasoning, isA<Map>());
          expect((reasoning as Map).containsKey('include'), isFalse);
          return okResponse();
        });

        await buildResponsesClient(client)
            .streamCompletion(
              _request(
                _messages(),
                modelConfig: _modelConfig(),
                reasoningEffort: ReasoningEffort.medium,
              ),
            )
            .drain<void>();
      },
    );

    test('reasoningEffort 为 null 时整个 reasoning 省略，store 仍为 false', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('reasoning'), isFalse);
        expect(payload['store'], false);
        return okResponse();
      });

      await buildResponsesClient(client)
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
          final payload =
              jsonDecode((request as http.Request).body)
                  as Map<String, dynamic>;
          sentEffort = (payload['reasoning'] as Map)['effort'] as String?;
          return okResponse();
        });

        await buildResponsesClient(client)
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

    test('请求日志合并自定义 header，反映最终实际请求头', () async {
      final logger = _FakeNetworkLogger();
      final client = _FakeStreamingHttpClient((_) async => okResponse());
      final responsesClient = buildResponsesClient(
        client,
        logger: logger,
        extraHeadersFactory: () => const {'X-Custom-Header': 'custom-value'},
      );

      await responsesClient
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
        buildResponsesClient(client)
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
    test('正文/推理流式产出 + completed → stop 归一化', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.reasoning_summary_text.delta","delta":"思考中"}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"第一段 "}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"第二段"}\n\n',
            ),
            utf8.encode('data: {"type":"response.completed"}\n\n'),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      final chunks = await buildResponsesClient(client)
          .streamCompletion(
            _request(
              _messages(),
              modelConfig: _modelConfig(),
              reasoningEffort: ReasoningEffort.medium,
            ),
          )
          .toList();

      expect(chunks.map((chunk) => chunk.reasoningDelta).toList(), [
        '思考中',
        '',
        '',
        '',
      ]);
      expect(chunks.map((chunk) => chunk.contentDelta).toList(), [
        '',
        '第一段 ',
        '第二段',
        '',
      ]);
      expect(chunks.last.finishReason, 'stop');
    });

    test('.done 带完整文本不重复累计（最终内容等于 delta 之和）', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"你好"}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"世界"}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.done","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"你好世界"}]}]}}\n\n',
            ),
          ]),
          200,
        );
      });

      final result = await buildResponsesClient(
        client,
      ).complete(_request(_messages(), modelConfig: _modelConfig()));

      expect(result.content, '你好世界');
    });

    test('仅 reasoning delta（无 output_text）→ 正常结束且推理保留', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.reasoning_summary_text.delta","delta":"思考中"}\n\n',
            ),
            utf8.encode('data: {"type":"response.completed"}\n\n'),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      final result = await buildResponsesClient(
        client,
      ).complete(_request(_messages(), modelConfig: _modelConfig()));

      expect(result.reasoningContent, '思考中');
      expect(result.content, isEmpty);
      expect(result.finishReason, 'stop');
    });

    test('超长空响应 rawSseData 截尾：responseBody 只保留尾部 200 行', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < 250; i++)
              utf8.encode('data: {"type":"response.created","seq":$i}\n\n'),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      try {
        await buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.responseBody, isNotNull);
        expect(error.responseBody!.split('\n'), hasLength(200));
        expect(
          error.responseBody,
          endsWith('data: {"type":"response.done","response":{"id":"r-1"}}'),
        );
      }
    });

    test('response.completed 携带 usage → 流尾部 chunk 填充用量', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"你好"}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":20,'
              '"output_tokens_details":{"reasoning_tokens":5},'
              '"input_tokens_details":{"cached_tokens":3}}}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      final chunks = await buildResponsesClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .toList();

      expect(chunks.map((chunk) => chunk.contentDelta).join(), '你好');
      expect(
        chunks.last.usage,
        const ChatGenerationUsage(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 3,
        ),
      );
    });

    test('incomplete + max_output_tokens → finishReason length', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.output_text.delta","delta":"部分输出"}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      final chunks = await buildResponsesClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .toList();

      expect(chunks.map((chunk) => chunk.contentDelta).join(), '部分输出');
      expect(chunks.last.finishReason, 'length');
    });

    test('非 2xx → ChatGenerationException 字段正确', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"bad key"}}')),
          401,
        );
      });

      await expectLater(
        buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.responses)
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
        buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.cause, 'cause', same(connectionError))
              .having((e) => e.causeStackTrace, 'causeStackTrace', isNotNull)
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.responses)
              .having((e) => e.uri, 'uri', testUri)
              .having(
                (e) => e.message,
                'message',
                contains('connection refused'),
              ),
        ),
      );
    });

    test('SSE 内 error 事件 → ChatGenerationException', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"error","message":"invalid api key","code":"invalid_api_key"}\n\n',
            ),
          ]),
          200,
        );
      });

      await expectLater(
        buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'invalid_api_key')
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.responses)
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('response.failed 事件 → ChatGenerationException', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"response.failed","response":{"error":{"code":"server_error","message":"Server had an error"}}}\n\n',
            ),
          ]),
          200,
        );
      });

      await expectLater(
        buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'Server had an error')
              .having((e) => e.apiErrorCode, 'apiErrorCode', 'server_error'),
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
        buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', contains('SSE 数据解析失败'))
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.responses)
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('空响应（无正文无推理）→ 无有效内容异常', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"type":"response.created"}\n\n'),
            utf8.encode(
              'data: {"type":"response.done","response":{"id":"r-1"}}\n\n',
            ),
          ]),
          200,
        );
      });

      try {
        await buildResponsesClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.message, contains('请求未返回有效内容'));
        expect(error.protocol, LlmApiProtocol.responses);
        expect(error.uri, testUri);
        expect(error.responseBody, contains('response.created'));
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
        final responsesClient = buildResponsesClient(
          client,
          decoder: _TimeoutDecoder(),
        );

        await expectLater(
          responsesClient
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
      final responsesClient = buildResponsesClient(client);

      final errors = <Object>[];
      // 以 Completer 等待超时错误，避免固定延时等待（仓库韧性门禁）。
      final errorArrived = Completer<void>();
      final subscription = responsesClient
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
  });
}

List<ChatRequestMessage> _messages() {
  return const [ChatRequestMessage(role: ChatMessageRole.user, content: '你好')];
}

LlmModelConfig _modelConfig({
  String apiUrl = 'https://api.example.com/v1/responses',
  LlmApiProtocol apiProtocol = LlmApiProtocol.responses,
}) {
  return LlmModelConfig(
    id: 'model-1',
    displayName: 'GPT-5',
    apiUrl: apiUrl,
    apiKey: 'sk-test-12345678',
    modelName: 'gpt-5',
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
