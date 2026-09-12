import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/core/logging/app_log_store.dart';
import 'package:oh_my_llm/core/logging/app_network_logger.dart';

void main() {
  test('工具请求关联兼容重发且默认日志不落参数、结果或错误回显', () async {
    final directory = await Directory.systemTemp.createTemp('llm-log-');
    final logger = AppNetworkLogger(
      store: await AppLogStore.open(directoryPath: directory.path),
    );
    try {
      final httpClient = _Http();
      final client = ChatCompletionsClient(
        transport: LlmHttpStreamTransport(
          httpClient: httpClient,
          logger: logger,
        ),
      );
      final request = LlmRequest(
        target: const LlmRequestTarget(
          protocol: LlmApiProtocol.chatCompletions,
          endpoint: 'https://example.com',
          apiKey: 'private-api-key',
          model: 'test',
        ),
        input: const [
          LlmTextMessage(role: LlmRole.user, text: 'private-prompt'),
        ],
        tools: [
          LlmToolDefinition(
            name: 'read',
            description: '读取',
            parameters: {'type': 'object'},
          ),
        ],
      );
      final result = await client.complete(request);
      await expectLater(
        client.complete(
          LlmRequest(
            target: request.target,
            input: [
              ...request.input,
              result.assistantTurn!,
              LlmToolResult(
                callId: 'a',
                name: 'read',
                output: 'private-result',
              ),
            ],
            tools: request.tools,
          ),
        ),
        throwsA(
          isA<LlmException>().having(
            (e) => e.responseBody,
            '显式诊断仍可用',
            contains('private-result'),
          ),
        ),
      );
      await logger.drain();
      final text = await File('${directory.path}/network.log').readAsString();
      for (final secret in [
        'private-api-key',
        'private-prompt',
        'private-argument',
        'private-result',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('requestId=${result.requestId} attempt=1'));
      expect(text, contains('requestId=${result.requestId} attempt=2'));
      expect(text, contains('"toolCallCount":1'));
      expect(text, contains('"cachedInputTokens":8'));
      expect(httpClient.sends, 3);
    } finally {
      await logger.drain();
      await directory.delete(recursive: true);
    }
  });
}

class _Http extends http.BaseClient {
  int sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    if (sends == 1) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('include_usage unsupported')),
        400,
      );
    }
    if (sends == 3) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('echo private-result')),
        500,
      );
    }
    final payload = jsonDecode((request as http.Request).body);
    expect(payload.containsKey('stream_options'), false);
    expect(payload['tools'], hasLength(1));
    final event = {
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'id': 'a',
                'type': 'function',
                'function': {
                  'name': 'read',
                  'arguments': '{"value":"private-argument"}',
                },
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
      'usage': {
        'prompt_tokens': 10,
        'prompt_tokens_details': {'cached_tokens': 8},
      },
    };
    return http.StreamedResponse(
      Stream.value(
        utf8.encode('data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n'),
      ),
      200,
    );
  }
}
