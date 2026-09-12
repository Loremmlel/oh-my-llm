import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/core/llm/protocols/responses/responses_client.dart';

void main() {
  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 编码显式输出上限和缓存配置', () async {
      Map<String, dynamic>? payload;
      final transport = LlmHttpStreamTransport(
        httpClient: _Http((request) {
          payload = jsonDecode((request as http.Request).body);
        }),
      );
      final client = switch (protocol) {
        LlmApiProtocol.chatCompletions => ChatCompletionsClient(
          transport: transport,
        ),
        LlmApiProtocol.responses => ResponsesClient(transport: transport),
        LlmApiProtocol.anthropic => AnthropicMessagesClient(
          transport: transport,
        ),
      };
      final options = switch (protocol) {
        LlmApiProtocol.chatCompletions => const ChatCompletionsOptions(
          promptCacheKey: 'novel',
        ),
        LlmApiProtocol.responses => const ResponsesOptions(
          promptCacheKey: 'novel',
        ),
        LlmApiProtocol.anthropic => const MessagesOptions(
          automaticCacheControl: true,
          cacheTtl: MessagesCacheTtl.oneHour,
        ),
      };
      await client.complete(
        LlmRequest(
          target: LlmRequestTarget(
            protocol: protocol,
            endpoint: 'https://example.com',
            apiKey: 'test',
            model: 'test',
          ),
          input: [],
          options: LlmGenerationOptions(
            maxOutputTokens: 256,
            protocolOptions: options,
          ),
        ),
      );
      final limit = switch (protocol) {
        LlmApiProtocol.chatCompletions => 'max_completion_tokens',
        LlmApiProtocol.responses => 'max_output_tokens',
        LlmApiProtocol.anthropic => 'max_tokens',
      };
      expect(payload![limit], 256);
      if (protocol == LlmApiProtocol.anthropic) {
        expect(payload!['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
      } else {
        expect(payload!['prompt_cache_key'], 'novel');
      }
    });
  }
  test('Responses 显式推理摘要不依赖同时配置 effort', () async {
    Map<String, dynamic>? payload;
    final client = ResponsesClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((request) {
          payload = jsonDecode((request as http.Request).body);
        }),
      ),
    );
    await client.complete(
      LlmRequest(
        target: const LlmRequestTarget(
          protocol: LlmApiProtocol.responses,
          endpoint: 'https://example.com',
          apiKey: 'test',
          model: 'test',
        ),
        input: [],
        options: const LlmGenerationOptions(
          protocolOptions: ResponsesOptions(
            reasoningSummary: ResponsesReasoningSummary.auto,
          ),
        ),
      ),
    );
    expect(payload!['reasoning'], {'summary': 'auto'});
  });

  test('错协议选项在发送前失败', () async {
    var sends = 0;
    final client = ChatCompletionsClient(
      transport: LlmHttpStreamTransport(
        httpClient: _Http((_) {
          sends++;
        }),
      ),
    );
    await expectLater(
      client.complete(
        LlmRequest(
          target: const LlmRequestTarget(
            protocol: LlmApiProtocol.chatCompletions,
            endpoint: 'https://example.com',
            apiKey: 'test',
            model: 'test',
          ),
          input: [],
          options: const LlmGenerationOptions(
            protocolOptions: MessagesOptions(),
          ),
        ),
      ),
      throwsA(
        isA<LlmException>().having(
          (e) => e.kind,
          '类型',
          LlmFailureKind.invalidRequest,
        ),
      ),
    );
    expect(sends, 0);
  });
}

class _Http extends http.BaseClient {
  _Http(this.onRequest);
  final void Function(http.BaseRequest) onRequest;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onRequest(request);
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}
