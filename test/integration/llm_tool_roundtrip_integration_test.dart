import '../helpers/fake_tool_protocol_http_client.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final httpClient = FakeToolProtocolHttpClient(protocol);
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
