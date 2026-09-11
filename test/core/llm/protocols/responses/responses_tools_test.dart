import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/responses/responses_client.dart';

LlmRequest _request(List<LlmInputItem> input) => LlmRequest(
  target: const LlmRequestTarget(
    protocol: LlmApiProtocol.responses,
    endpoint: 'https://example.com',
    apiKey: 'test',
    model: 'test',
  ),
  input: input,
  tools: [
    LlmToolDefinition(
      name: 'read',
      description: '读取',
      parameters: {'type': 'object'},
    ),
  ],
);

void main() {
  test('只有终态完整正文时 complete 返回原文且不伪造增量', () async {
    final client = ResponsesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http(
          (_) => [
            {
              'type': 'response.completed',
              'response': {
                'output': [
                  {
                    'type': 'message',
                    'id': 'm',
                    'role': 'assistant',
                    'content': [
                      {'type': 'output_text', 'text': '最终正文'},
                    ],
                  },
                ],
              },
            },
          ],
        ),
      ),
    );
    final events = await client.streamCompletion(_request([])).toList();
    expect(events.map((e) => e.contentDelta).join(), isEmpty);
    expect(events.whereType<LlmCompleted>().single.result.content, '最终正文');
    expect(
      events.whereType<LlmCompleted>().single.result.assistantTurn!.text,
      '最终正文',
    );
  });

  test('拒绝内容保留原始终态并标准化为 refused', () async {
    final client = ResponsesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http(
          (_) => [
            {'type': 'response.refusal.delta', 'delta': '拒绝说明'},
            {
              'type': 'response.completed',
              'response': {
                'output': [
                  {
                    'type': 'message',
                    'id': 'm',
                    'role': 'assistant',
                    'content': [
                      {'type': 'refusal', 'refusal': '拒绝说明'},
                    ],
                  },
                ],
              },
            },
          ],
        ),
      ),
    );
    final result = await client.complete(_request([]));
    expect(result.stopKind, LlmStopKind.refused);
    expect(result.finishReason, 'completed');
    expect(result.content, '拒绝说明');
  });

  test('完成的 reasoning 与 function item 按顺序无状态回传且不重复参数', () async {
    final wires = <Map<String, dynamic>>[];
    final reasoning = {
      'type': 'reasoning',
      'id': 'r',
      'summary': <Object?>[],
      'encrypted_content': 'opaque',
    };
    final call = {
      'type': 'function_call',
      'id': 'item_id',
      'call_id': 'call_id',
      'name': 'read',
      'arguments': '{"角色":"甲"}',
    };
    final client = ResponsesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((request) {
          wires.add(jsonDecode((request as http.Request).body));
          if (wires.length == 2) {
            return [
              {'type': 'response.output_text.delta', 'delta': '已读取'},
              {
                'type': 'response.completed',
                'response': {
                  'output': [
                    {
                      'type': 'message',
                      'id': 'm',
                      'role': 'assistant',
                      'content': [
                        {'type': 'output_text', 'text': '已读取'},
                      ],
                    },
                  ],
                },
              },
            ];
          }
          return [
            {
              'type': 'response.output_item.added',
              'output_index': 0,
              'item': {...reasoning, 'encrypted_content': ''},
            },
            {
              'type': 'response.output_item.done',
              'output_index': 0,
              'item': reasoning,
            },
            {
              'type': 'response.output_item.added',
              'output_index': 1,
              'item': {...call, 'arguments': ''},
            },
            {
              'type': 'response.function_call_arguments.delta',
              'output_index': 1,
              'item_id': 'item_id',
              'delta': '{"角色":',
            },
            {
              'type': 'response.function_call_arguments.delta',
              'output_index': 1,
              'item_id': 'item_id',
              'delta': '"甲"}',
            },
            {
              'type': 'response.function_call_arguments.done',
              'output_index': 1,
              'item_id': 'item_id',
              'arguments': call['arguments'],
            },
            {
              'type': 'response.output_item.done',
              'output_index': 1,
              'item': call,
            },
            {
              'type': 'response.completed',
              'response': {
                'output': [reasoning, call],
              },
            },
          ];
        }),
      ),
    );
    final request = _request(const [
      LlmTextMessage(role: LlmRole.user, text: '读取角色'),
    ]);
    final first = await client.complete(request);
    expect(first.toolCalls.single.arguments['角色'], '甲');
    expect(first.stopKind, LlmStopKind.toolCalls);
    final second = await client.complete(
      _request([
        ...request.input,
        first.assistantTurn!,
        LlmToolResult(callId: 'call_id', name: 'read', output: '角色卡'),
      ]),
    );
    expect(second.content, '已读取');
    expect(wires.last['store'], false);
    expect(wires.last.containsKey('previous_response_id'), false);
    expect(wires.last['include'], ['reasoning.encrypted_content']);
    expect((wires.last['input'] as List)[1], reasoning);
    expect((wires.last['input'] as List)[2], call);
    expect((wires.last['input'] as List)[3]['call_id'], 'call_id');
  });

  for (final terminal in ['response.incomplete', 'EOF']) {
    test('$terminal 不提交已经收到的工具参数', () async {
      final client = ResponsesClient(
        transport: LlmHttpStreamTransport(
          httpClient: _Http(
            (_) => [
              {
                'type': 'response.output_item.done',
                'output_index': 0,
                'item': {
                  'type': 'function_call',
                  'id': 'i',
                  'call_id': 'c',
                  'name': 'read',
                  'arguments': '{}',
                },
              },
              if (terminal != 'EOF')
                {
                  'type': terminal,
                  'response': {
                    'incomplete_details': {'reason': 'max_output_tokens'},
                  },
                },
            ],
          ),
        ),
      );
      await expectLater(
        client.complete(_request(const [])),
        throwsA(isA<LlmException>()),
      );
    });
  }
}

class _Http extends http.BaseClient {
  _Http(this.handler);
  final List<Map<String, Object?>> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.fromIterable(
          handler(request)
              .map((event) => utf8.encode('data: ${jsonEncode(event)}\n\n')),
        ),
        200,
      );
}
