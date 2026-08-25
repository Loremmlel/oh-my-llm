import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/http/sse_event_decoder.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

void main() {
  final testUri = Uri.parse('https://api.example.com/v1/messages');

  AnthropicMessagesClient buildAnthropicClient(
    http.Client httpClient, {
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
    SseEventDecoder decoder = const SseEventDecoder(),
  }) {
    return AnthropicMessagesClient(
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
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\n',
        ),
        utf8.encode(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        ),
        utf8.encode('data: {"type":"message_stop"}\n\n'),
      ]),
      200,
    );
  }

  // ── 请求编码（外部协议契约）──────────────────────────────────

  group('请求编码', () {
    test('客户端将原始 API 根解析为 Anthropic Messages 端点', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.method, 'POST');
        expect(request.url, testUri);
        return okResponse();
      });

      await buildAnthropicClient(client)
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
        buildAnthropicClient(client)
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
                LlmApiProtocol.anthropic,
              )
              .having((error) => error.uri, 'uri', isNull),
        ),
      );
      expect(sent, isFalse);
    });

    test('Header 逐字：x-api-key 与 anthropic-version', () async {
      final client = _FakeStreamingHttpClient((request) async {
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['Accept'], 'text/event-stream');
        expect(request.headers['x-api-key'], 'sk-ant-test-12345678');
        expect(request.headers['anthropic-version'], '2023-06-01');
        return okResponse();
      });

      await buildAnthropicClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test(
      '请求体逐字：max_tokens/cache_control/system/thinking/output_config',
      () async {
        final client = _FakeStreamingHttpClient((request) async {
          final payload = jsonDecode(
            (request as http.Request).body,
          ) as Map<String, dynamic>;
          expect(payload, {
            'model': 'claude-4',
            'stream': true,
            'max_tokens': 8192,
            'cache_control': {'type': 'ephemeral'},
            'system': '系统提示\n系统补充',
            'messages': [
              {'role': 'user', 'content': '你好'},
              {'role': 'assistant', 'content': '回复'},
            ],
            'thinking': {'type': 'adaptive', 'display': 'summarized'},
            'output_config': {'effort': 'medium'},
          });
          return okResponse();
        });

        await buildAnthropicClient(client)
            .streamCompletion(
              _request(
                const [
                  ChatRequestMessage(
                    role: ChatMessageRole.system,
                    content: '系统提示',
                  ),
                  ChatRequestMessage(
                    role: ChatMessageRole.system,
                    content: '系统补充',
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
      },
    );

    test('无 leading System → 顶层 system 省略', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('system'), isFalse);
        return okResponse();
      });

      await buildAnthropicClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test('reasoningEffort 为 null → thinking 与 output_config 省略', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        expect(payload.containsKey('thinking'), isFalse);
        expect(payload.containsKey('output_config'), isFalse);
        return okResponse();
      });

      await buildAnthropicClient(client)
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();
    });

    test('effort 映射：low→low、medium→medium、high→high、xhigh/max→max', () async {
      const expectedEfforts = <ReasoningEffort, String>{
        ReasoningEffort.low: 'low',
        ReasoningEffort.medium: 'medium',
        ReasoningEffort.high: 'high',
        ReasoningEffort.xhigh: 'max',
        ReasoningEffort.max: 'max',
      };

      for (final entry in expectedEfforts.entries) {
        String? sentEffort;
        final client = _FakeStreamingHttpClient((request) async {
          final payload = jsonDecode(
            (request as http.Request).body,
          ) as Map<String, dynamic>;
          sentEffort = (payload['output_config'] as Map)['effort'] as String?;
          expect(
            (payload['thinking'] as Map)['type'],
            'adaptive',
            reason: entry.key.name,
          );
          expect(
            (payload['thinking'] as Map)['display'],
            'summarized',
            reason: entry.key.name,
          );
          return okResponse();
        });

        await buildAnthropicClient(client)
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

    test('消息数组已转换：无 system role、无相邻同角色、只含 content', () async {
      final client = _FakeStreamingHttpClient((request) async {
        final payload =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        final messages = (payload['messages'] as List).cast<Map>();
        expect(messages, hasLength(3));
        for (final message in messages) {
          expect(['user', 'assistant'], contains(message['role']));
          // 历史 reasoning 不编入请求：请求消息只含 role/content 两个键。
          expect(message.keys.toSet(), {'role', 'content'});
        }
        expect(messages[0]['role'], 'user');
        expect(messages[0]['content'], '开头\n中间指令');
        expect(messages[1]['role'], 'assistant');
        expect(messages[2]['role'], 'user');
        return okResponse();
      });

      await buildAnthropicClient(client)
          .streamCompletion(
            _request(const [
              ChatRequestMessage(role: ChatMessageRole.user, content: '开头'),
              ChatRequestMessage(role: ChatMessageRole.system, content: '中间指令'),
              ChatRequestMessage(
                role: ChatMessageRole.assistant,
                content: '回复',
              ),
              ChatRequestMessage(role: ChatMessageRole.user, content: '追问'),
            ], modelConfig: _modelConfig()),
          )
          .drain<void>();
    });

    test('请求日志合并自定义 header，反映最终实际请求头', () async {
      final logger = _FakeNetworkLogger();
      final client = _FakeStreamingHttpClient((_) async => okResponse());
      final anthropicClient = buildAnthropicClient(
        client,
        logger: logger,
        extraHeadersFactory: () => const {'X-Custom-Header': 'custom-value'},
      );

      await anthropicClient
          .streamCompletion(_request(_messages(), modelConfig: _modelConfig()))
          .drain<void>();

      expect(logger.requestHeaders!['Content-Type'], 'application/json');
      expect(logger.requestHeaders!['x-api-key'], 'sk-ant-test-12345678');
      expect(logger.requestHeaders!['anthropic-version'], '2023-06-01');
      expect(logger.requestHeaders!['X-Custom-Header'], 'custom-value');
    });

    test('协议不匹配 → ChatGenerationException，且不发送请求', () async {
      final client = _FakeStreamingHttpClient((_) async {
        throw UnimplementedError('协议不匹配时不应发送请求');
      });

      await expectLater(
        buildAnthropicClient(client)
            .streamCompletion(
              _request(
                _messages(),
                modelConfig: _modelConfig(
                  apiProtocol: LlmApiProtocol.responses,
                ),
              ),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.protocol,
            'protocol',
            LlmApiProtocol.responses,
          ),
        ),
      );
    });
  });

  // ── 行为等价（流式集成，经 transport + 假 http.Client）─────────

  group('行为等价', () {
    test('正文/推理流式产出 + end_turn → stop 归一化', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"思考中"}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"第一段 "}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"第二段"}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
            ),
            utf8.encode('data: {"type":"message_stop"}\n\n'),
          ]),
          200,
        );
      });

      final chunks = await buildAnthropicClient(client)
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

    test('原生两阶段 usage 经 client 与 complete 合并为完整用量', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"message_start","message":{"usage":{"input_tokens":10,'
              '"cache_creation_input_tokens":4,"cache_read_input_tokens":3}}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"message_delta","usage":{"output_tokens":20},'
              '"delta":{"stop_reason":"end_turn"}}\n\n',
            ),
            utf8.encode('data: {"type":"message_stop"}\n\n'),
          ]),
          200,
        );
      });

      final result = await buildAnthropicClient(client)
          .complete(_request(_messages(), modelConfig: _modelConfig()));

      expect(result.content, '你好');
      expect(result.finishReason, 'stop');
      expect(
        result.usage,
        const ChatGenerationUsage(
          inputTokens: 10,
          outputTokens: 20,
          cachedInputTokens: 3,
        ),
      );
    });

    test('stop_sequence → stop；model_context_window_exceeded → length', () async {
      Future<String?> lastFinishReason(String stopReason) async {
        final client = _FakeStreamingHttpClient((_) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"部分输出"}}\n\n',
              ),
              utf8.encode(
                'data: {"type":"message_delta","delta":{"stop_reason":"$stopReason"}}\n\n',
              ),
              utf8.encode('data: {"type":"message_stop"}\n\n'),
            ]),
            200,
          );
        });

        final chunks = await buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .toList();
        return chunks.last.finishReason;
      }

      expect(await lastFinishReason('stop_sequence'), 'stop');
      expect(await lastFinishReason('model_context_window_exceeded'), 'length');
    });

    test('只有推理、无正文 → 保留推理正常结束', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"完整思考"}}\n\n',
            ),
            utf8.encode(
              'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
            ),
            utf8.encode('data: {"type":"message_stop"}\n\n'),
          ]),
          200,
        );
      });

      final result = await buildAnthropicClient(client)
          .complete(_request(_messages(), modelConfig: _modelConfig()));

      expect(result.reasoningContent, '完整思考');
      expect(result.content, isEmpty);
    });

    test('非 2xx → ChatGenerationException 字段正确', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode('{"type":"error","error":{"message":"bad key"}}'),
          ),
          401,
        );
      });

      await expectLater(
        buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
              .having((e) => e.uri, 'uri', testUri)
              .having(
                (e) => e.responseBody,
                'responseBody',
                '{"type":"error","error":{"message":"bad key"}}',
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
        buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.cause, 'cause', same(connectionError))
              .having((e) => e.causeStackTrace, 'causeStackTrace', isNotNull)
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
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
              'data: {"type":"error","error":{"type":"invalid_request_error","message":"invalid api key"}}\n\n',
            ),
          ]),
          200,
        );
      });

      await expectLater(
        buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having(
                (e) => e.apiErrorCode,
                'apiErrorCode',
                'invalid_request_error',
              )
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('意外 tool_use 内容块 → 明确不支持异常', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t-1","name":"f","input":{}}}\n\n',
            ),
          ]),
          200,
        );
      });

      await expectLater(
        buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', contains('不支持该响应类型'))
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
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
        buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>(),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.message, 'message', contains('SSE 数据解析失败'))
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
              .having((e) => e.uri, 'uri', testUri),
        ),
      );
    });

    test('空响应（无正文无推理）→ 无有效内容异常', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"type":"ping"}\n\n'),
            utf8.encode('data: {"type":"message_stop"}\n\n'),
          ]),
          200,
        );
      });

      try {
        await buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.message, contains('请求未返回有效内容'));
        expect(error.protocol, LlmApiProtocol.anthropic);
        expect(error.uri, testUri);
        expect(error.responseBody, contains('ping'));
      }
    });

    test('超长空响应 rawSseData 截尾：responseBody 只保留尾部 200 行', () async {
      final client = _FakeStreamingHttpClient((_) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < 250; i++)
              utf8.encode('data: {"type":"ping","seq":$i}\n\n'),
            utf8.encode('data: {"type":"message_stop"}\n\n'),
          ]),
          200,
        );
      });

      try {
        await buildAnthropicClient(client)
            .streamCompletion(
              _request(_messages(), modelConfig: _modelConfig()),
            )
            .drain<void>();
        fail('Expected ChatGenerationException');
      } on ChatGenerationException catch (error) {
        expect(error.responseBody, isNotNull);
        expect(error.responseBody!.split('\n'), hasLength(200));
        expect(error.responseBody, endsWith('data: {"type":"message_stop"}'));
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
        final anthropicClient = buildAnthropicClient(
          client,
          decoder: _TimeoutDecoder(),
        );

        await expectLater(
          anthropicClient
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
      final anthropicClient = buildAnthropicClient(client);

      final errors = <Object>[];
      // 以 Completer 等待超时错误，避免固定延时等待（仓库韧性门禁）。
      final errorArrived = Completer<void>();
      final subscription = anthropicClient
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
  String apiUrl = 'https://api.example.com/v1/messages',
  LlmApiProtocol apiProtocol = LlmApiProtocol.anthropic,
}) {
  return LlmModelConfig(
    id: 'model-1',
    displayName: 'Claude',
    apiUrl: apiUrl,
    apiKey: 'sk-ant-test-12345678',
    modelName: 'claude-4',
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
