import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/anthropic/anthropic_messages_client.dart';

LlmRequest _request(List<LlmInputItem> input) => LlmRequest(
  target: const LlmRequestTarget(
    protocol: LlmApiProtocol.anthropic,
    endpoint: 'https://example.com',
    apiKey: 'test',
    model: 'test',
  ),
  input: input,
  options: const LlmGenerationOptions(maxOutputTokens: 100),
  tools: [
    LlmToolDefinition(
      name: 'read',
      description: '读取',
      parameters: {'type': 'object'},
    ),
  ],
);

void main() {
  test('工具结果回传时保留 thinking 签名和 redacted 块顺序', () async {
    final wires = <Map<String, dynamic>>[];
    final client = AnthropicMessagesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((request) {
          wires.add(jsonDecode((request as http.Request).body));
          if (wires.length == 2) {
            return [
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {'type': 'text', 'text': ''},
              },
              {
                'type': 'content_block_delta',
                'index': 0,
                'delta': {'type': 'text_delta', 'text': '已读取'},
              },
              {'type': 'content_block_stop', 'index': 0},
              {
                'type': 'message_delta',
                'delta': {'stop_reason': 'end_turn'},
              },
              {'type': 'message_stop'},
            ];
          }
          return [
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'thinking', 'thinking': ''},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'thinking_delta', 'thinking': '摘要'},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'signature_delta', 'signature': 'sig'},
            },
            {'type': 'content_block_stop', 'index': 0},
            {
              'type': 'content_block_start',
              'index': 1,
              'content_block': {'type': 'redacted_thinking', 'data': 'opaque'},
            },
            {'type': 'content_block_stop', 'index': 1},
            {
              'type': 'content_block_start',
              'index': 2,
              'content_block': {
                'type': 'tool_use',
                'id': 'a',
                'name': 'read',
                'input': {},
              },
            },
            {
              'type': 'content_block_delta',
              'index': 2,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': '{"角色":"甲"}',
              },
            },
            {'type': 'content_block_stop', 'index': 2},
            {
              'type': 'content_block_start',
              'index': 3,
              'content_block': {
                'type': 'tool_use',
                'id': 'b',
                'name': 'read',
                'input': {'角色': '乙'},
              },
            },
            {'type': 'content_block_stop', 'index': 3},
            {
              'type': 'message_delta',
              'delta': {'stop_reason': 'tool_use'},
              'usage': {'output_tokens': 10},
            },
            {'type': 'message_stop'},
          ];
        }),
      ),
    );
    final request = _request(const [
      LlmTextMessage(role: LlmRole.user, text: '读取'),
    ]);
    final result = await client.complete(request);
    expect(result.toolCalls.map((call) => call.arguments['角色']), ['甲', '乙']);
    expect(result.reasoningContent, '摘要');
    final next = await client.complete(
      _request([
        ...request.input,
        result.assistantTurn!,
        for (final call in result.toolCalls)
          LlmToolResult(
            callId: call.callId,
            name: call.name,
            output: '角色卡',
            isError: call.callId == 'b',
          ),
      ]),
    );
    expect(next.content, '已读取');
    final messages = wires.last['messages'] as List;
    expect(messages[1]['content'][0], {
      'type': 'thinking',
      'thinking': '摘要',
      'signature': 'sig',
    });
    expect(messages[1]['content'][1], {
      'type': 'redacted_thinking',
      'data': 'opaque',
    });
    expect(messages[2]['content'], hasLength(2));
    expect(messages[2]['content'][1]['is_error'], true);
    expect(messages[2]['content'][1]['tool_use_id'], 'b');
  });
  test('工具块未停止或消息未结束时不能发布调用', () async {
    final client = AnthropicMessagesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http(
          (_) => [
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {
                'type': 'tool_use',
                'id': 'a',
                'name': 'read',
                'input': {},
              },
            },
            {
              'type': 'message_delta',
              'delta': {'stop_reason': 'tool_use'},
            },
            {'type': 'message_stop'},
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
