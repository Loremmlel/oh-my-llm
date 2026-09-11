import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/protocols/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/core/llm/protocols/protocol_routing_llm_client.dart';
import 'package:oh_my_llm/core/llm/protocols/responses/responses_client.dart';

void main() {
  test('按协议路由到且只路由到对应客户端（同一请求对象）', () async {
    final spies = _SpyClients();
    final router = spies.router;

    for (final protocol in LlmApiProtocol.values) {
      // 每个协议一轮独立记录，避免上一轮请求污染本轮断言。
      spies.reset();

      final request = _request(protocol);

      final chunks = await router.streamCompletion(request).toList();

      final expectedSpy = spies.expected(protocol);
      expect(expectedSpy.requests, [
        same(request),
      ], reason: '${protocol.name} 应把原请求对象交给对应客户端');

      for (final other in spies.others(protocol)) {
        expect(
          other.requests,
          isEmpty,
          reason: '${protocol.name} 请求不应进入 ${other.protocol.name} 客户端',
        );
      }
      // 委派流原样透传：chunk 实例与产生方一致，不做复制或改写。
      expect(chunks.single, same(expectedSpy.emittedChunk));
    }
  });

  test('complete() 继承基类折叠，只消费对应客户端的流式输出', () async {
    final spies = _SpyClients();
    final router = spies.router;

    final result = await router.complete(_request(LlmApiProtocol.responses));

    expect(result.content, 'responses-正文');
    expect(result.reasoningContent, 'responses-推理');
    expect(result.finishReason, 'stop');
    expect(spies.responses.requests, hasLength(1));
    expect(spies.chatCompletions.requests, isEmpty);
    expect(spies.anthropic.requests, isEmpty);
  });

  test('委派异常保留原始诊断并补充调用标识', () async {
    final spies = _SpyClients();
    final router = spies.router;
    final error = LlmException(
      '协议不匹配：Responses 客户端只能处理 responses 协议请求',
      protocol: LlmApiProtocol.chatCompletions,
    );
    spies.responses.failures.add(error);

    await expectLater(
      router.streamCompletion(_request(LlmApiProtocol.responses)).drain<void>(),
      throwsA(
        isA<LlmException>()
            .having((e) => e.message, '消息', error.message)
            .having((e) => e.protocol, '协议', error.protocol)
            .having((e) => e.requestId, '调用标识', isNotEmpty),
      ),
    );
  });
}

class _SpyClients {
  final chatCompletions = _SpyClient(
    protocol: LlmApiProtocol.chatCompletions,
    emittedChunk: const LlmEvent(contentDelta: 'cc-正文'),
  );
  final responses = _SpyClient(
    protocol: LlmApiProtocol.responses,
    emittedChunk: const LlmEvent(
      contentDelta: 'responses-正文',
      reasoningDelta: 'responses-推理',
      finishReason: 'stop',
    ),
  );
  final anthropic = _SpyClient(
    protocol: LlmApiProtocol.anthropic,
    emittedChunk: const LlmEvent(contentDelta: 'anthropic-正文'),
  );

  ProtocolRoutingLlmClient get router => ProtocolRoutingLlmClient(
    chatCompletions: chatCompletions,
    responses: responses,
    anthropic: anthropic,
  );

  _SpyClient expected(LlmApiProtocol protocol) {
    return switch (protocol) {
      LlmApiProtocol.chatCompletions => chatCompletions,
      LlmApiProtocol.responses => responses,
      LlmApiProtocol.anthropic => anthropic,
    };
  }

  Iterable<_SpyClient> others(LlmApiProtocol protocol) {
    return [
      for (final spy in [chatCompletions, responses, anthropic])
        if (spy.protocol != protocol) spy,
    ];
  }

  void reset() {
    for (final spy in [chatCompletions, responses, anthropic]) {
      spy.requests.clear();
      spy.failures.clear();
    }
  }
}

LlmRequest _request(LlmApiProtocol protocol) {
  return LlmRequest(
    target: LlmRequestTarget(
      protocol: protocol,
      endpoint: 'https://api.example.com/v1',
      apiKey: 'sk-test-12345678',
      model: 'test-model',
    ),
    input: const [LlmTextMessage(role: LlmRole.user, text: '你好')],
  );
}

/// 记录型假客户端：实现三种具体客户端之一，记录收到的请求，
/// 产出固定 chunk，并可注入失败。
class _SpyClient extends LlmClient
    implements ChatCompletionsClient, ResponsesClient, AnthropicMessagesClient {
  _SpyClient({required this.protocol, required this.emittedChunk});

  final LlmApiProtocol protocol;
  final LlmEvent emittedChunk;
  final List<LlmRequest> requests = [];
  final List<Object> failures = [];

  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) async* {
    requests.add(request);
    for (final failure in failures) {
      throw failure;
    }
    yield emittedChunk;
  }
}
