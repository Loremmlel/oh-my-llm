import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';

LlmRequest request({List<LlmInputItem>? input}) => LlmRequest(
  target: const LlmRequestTarget(
    protocol: LlmApiProtocol.chatCompletions,
    endpoint: 'https://example.com',
    apiKey: 'test',
    model: 'test',
  ),
  input: input ?? const [LlmTextMessage(role: LlmRole.user, text: '读取角色')],
  tools: [
    LlmToolDefinition(
      name: 'read_character',
      description: '读取人物',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
    ),
  ],
);

void main() {
  test('交错参数片段构成完整工具调用且可回传结果', () async {
    final requests = <Map<String, dynamic>>[];
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((wire) {
          requests.add(
            jsonDecode((wire as http.Request).body) as Map<String, dynamic>,
          );
          if (requests.length == 2) {
            return [
              '{"choices":[{"delta":{"content":"已读取"},"finish_reason":"stop"}]}',
              '[DONE]',
            ];
          }
          return [
            jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_a',
                        'type': 'function',
                        'function': {
                          'name': 'read_character',
                          'arguments': '{"na',
                        },
                      },
                      {
                        'index': 1,
                        'id': 'call_b',
                        'type': 'function',
                        'function': {
                          'name': 'read_character',
                          'arguments': '{"name":"乙"}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'function': {'arguments': 'me":"甲"}'},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
            '{"choices":[],"usage":{"prompt_tokens":30,"completion_tokens":12}}',
            '[DONE]',
          ];
        }),
      ),
    );
    final firstRequest = request();
    final result = await client.complete(firstRequest);
    expect(result.stopKind, LlmStopKind.toolCalls);
    expect(result.toolCalls.map((call) => call.arguments['name']), ['甲', '乙']);
    expect(result.usage!.inputTokens, 30);
    final next = await client.complete(
      request(
        input: [
          ...firstRequest.input,
          result.assistantTurn!,
          for (final call in result.toolCalls)
            LlmToolResult(callId: call.callId, name: call.name, output: '角色信息'),
        ],
      ),
    );
    expect(next.content, '已读取');
    expect(
      (requests.first['tools'] as List).single['function']['strict'],
      false,
    );
    final messages = requests.last['messages'] as List;
    expect(messages[1]['tool_calls'], hasLength(2));
    expect(messages[2]['tool_call_id'], 'call_a');
    expect(messages[3]['tool_call_id'], 'call_b');
  });

  test('完整 message 回退支持工具且正文不会丢失', () async {
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http(
          (_) => [
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '先读取',
                    'tool_calls': [
                      {
                        'id': 'a',
                        'type': 'function',
                        'function': {
                          'name': 'read_character',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
          ],
        ),
      ),
    );
    final result = await client.complete(request());
    expect(result.content, '先读取');
    expect(result.toolCalls.single.callId, 'a');
  });
  for (final count in [32, 33]) {
    test('每轮 $count 个工具调用遵守数量边界', () async {
      final client = ChatCompletionsClient(
        transport: LlmHttpStreamTransport(
          httpClient: _Http(
            (_) => [
              jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        for (var i = 0; i < count; i++)
                          {
                            'index': i,
                            'id': 'call_$i',
                            'type': 'function',
                            'function': {
                              'name': 'read_character',
                              'arguments': '{}',
                            },
                          },
                      ],
                    },
                    'finish_reason': 'tool_calls',
                  },
                ],
              }),
            ],
          ),
        ),
      );
      if (count == 32) {
        expect((await client.complete(request())).toolCalls, hasLength(32));
      } else {
        await expectLater(
          client.complete(request()),
          throwsA(isA<LlmException>()),
        );
      }
    });
  }

  for (final scenario in ['截断参数', '缺少终态', '未知工具', '重复调用ID']) {
    test('$scenario 不发布可执行工具调用', () async {
      final call = {
        'index': 0,
        'id': 'a',
        'type': 'function',
        'function': {
          'name': scenario == '未知工具' ? 'shell' : 'read_character',
          'arguments': scenario == '截断参数' ? '{' : '{}',
        },
      };
      final client = ChatCompletionsClient(
        transport: LlmHttpStreamTransport(
          httpClient: _Http(
            (_) => [
              jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        call,
                        if (scenario == '重复调用ID') {...call, 'index': 1},
                      ],
                    },
                    if (scenario != '缺少终态') 'finish_reason': 'tool_calls',
                  },
                ],
              }),
              '[DONE]',
            ],
          ),
        ),
      );
      await expectLater(
        client.complete(request()),
        throwsA(isA<LlmException>()),
      );
    });
  }
}

class _Http extends http.BaseClient {
  _Http(this.handler);
  final List<String> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.fromIterable(
          handler(request).map((line) => utf8.encode('data: $line\n\n')),
        ),
        200,
      );
}
