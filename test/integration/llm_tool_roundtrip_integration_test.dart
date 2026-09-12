import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/app/composition/llm_bindings.dart';
import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';

void main() {
  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 经生产装配完成工具往返且测试处理器只运行一次', () async {
      final httpClient = _Wire(protocol);
      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            CustomHeadersHttpClient(httpClient, const {}),
          ),
          customHeadersMapProvider.overrideWithValue(const {}),
          appNetworkLoggerProvider.overrideWithValue(const NoopNetworkLogger()),
        ],
      );
      addTearDown(container.dispose);
      final client = container.read(llmClientProvider);
      final target = LlmRequestTarget(
        protocol: protocol,
        endpoint: 'https://example.com',
        apiKey: 'test',
        model: 'test',
      );
      final tools = [
        LlmToolDefinition(
          name: 'read',
          description: '读取角色',
          parameters: {'type': 'object'},
        ),
      ];
      const input = [
        LlmTextMessage(role: LlmRole.system, text: '写作规则'),
        LlmTextMessage(role: LlmRole.user, text: '读取角色'),
      ];
      final request = LlmRequest(
        target: target,
        input: input,
        tools: tools,
        options: const LlmGenerationOptions(maxOutputTokens: 100),
      );
      final first = await client.complete(request);
      var executions = 0;
      final results = [
        for (final call in first.toolCalls)
          (() {
            expect(call.name, 'read');
            expect(call.arguments, isEmpty);
            executions++;
            return LlmToolResult(
              callId: call.callId,
              name: call.name,
              output: '角色卡',
            );
          })(),
      ];
      final second = await client.complete(
        LlmRequest(
          target: target,
          input: [...input, first.assistantTurn!, ...results],
          tools: tools,
          options: request.options,
        ),
      );
      expect(second.content, '完成');
      expect(executions, 1);
      expect(httpClient.requests, hasLength(2));
      expect(first.requestId, isNotEmpty);
      expect(second.requestId, isNot(first.requestId));
      final key = protocol == LlmApiProtocol.responses ? 'input' : 'messages';
      final prefixLength = protocol == LlmApiProtocol.anthropic ? 1 : 2;
      expect(
        (httpClient.requests.last[key] as List).take(prefixLength).toList(),
        httpClient.requests.first[key],
      );
    });
  }
}

class _Wire extends http.BaseClient {
  _Wire(this.protocol);
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
                          'function': {'name': 'read', 'arguments': '{}'},
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
                      'name': 'read',
                      'arguments': '{}',
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
              ? {'type': 'tool_use', 'id': 'c', 'name': 'read', 'input': {}}
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
