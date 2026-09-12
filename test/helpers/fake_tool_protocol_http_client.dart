import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

class FakeToolProtocolHttpClient extends http.BaseClient {
  FakeToolProtocolHttpClient(
    this.protocol, {
    this.toolName = 'read',
    this.arguments = const {},
  });
  final String toolName;
  final Map<String, Object?> arguments;
  final LlmApiProtocol protocol;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(jsonDecode((request as http.Request).body));
    final first = requests.length == 1;
    final events = switch (protocol) {
      LlmApiProtocol.chatCompletions => [
        {
          'choices': [
            {
              'delta': first
                  ? {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'c',
                          'type': 'function',
                          'function': {
                            'name': toolName,
                            'arguments': jsonEncode(arguments),
                          },
                        },
                      ],
                    }
                  : {'content': '完成'},
              'finish_reason': first ? 'tool_calls' : 'stop',
            },
          ],
        },
      ],
      LlmApiProtocol.responses => [
        if (!first) {'type': 'response.output_text.delta', 'delta': '完成'},
        {
          'type': 'response.completed',
          'response': {
            'output': [
              first
                  ? {
                      'type': 'function_call',
                      'id': 'i',
                      'call_id': 'c',
                      'name': toolName,
                      'arguments': jsonEncode(arguments),
                    }
                  : {
                      'type': 'message',
                      'id': 'm',
                      'role': 'assistant',
                      'content': [
                        {'type': 'output_text', 'text': '完成'},
                      ],
                    },
            ],
          },
        },
      ],
      LlmApiProtocol.anthropic => [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': first
              ? {
                  'type': 'tool_use',
                  'id': 'c',
                  'name': toolName,
                  'input': arguments,
                }
              : {'type': 'text', 'text': ''},
        },
        if (!first)
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': '完成'},
          },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': first ? 'tool_use' : 'end_turn'},
        },
        {'type': 'message_stop'},
      ],
    };
    return http.StreamedResponse(
      Stream.fromIterable([
        for (final event in events)
          utf8.encode('data: ${jsonEncode(event)}\n\n'),
        if (protocol == LlmApiProtocol.chatCompletions)
          utf8.encode('data: [DONE]\n\n'),
      ]),
      200,
    );
  }
}
