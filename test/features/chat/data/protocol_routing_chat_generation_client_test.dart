import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/data/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/data/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

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

  test('委派异常原样透传（同一实例，不包装不重试）', () async {
    final spies = _SpyClients();
    final router = spies.router;
    final error = ChatGenerationException(
      '协议不匹配：Responses 客户端只能处理 responses 协议请求',
      protocol: LlmApiProtocol.chatCompletions,
    );
    spies.responses.failures.add(error);

    await expectLater(
      router.streamCompletion(_request(LlmApiProtocol.responses)).drain<void>(),
      throwsA(same(error)),
    );
  });
}

class _SpyClients {
  final chatCompletions = _SpyClient(
    protocol: LlmApiProtocol.chatCompletions,
    emittedChunk: const ChatGenerationChunk(contentDelta: 'cc-正文'),
  );
  final responses = _SpyClient(
    protocol: LlmApiProtocol.responses,
    emittedChunk: const ChatGenerationChunk(
      contentDelta: 'responses-正文',
      reasoningDelta: 'responses-推理',
      finishReason: 'stop',
    ),
  );
  final anthropic = _SpyClient(
    protocol: LlmApiProtocol.anthropic,
    emittedChunk: const ChatGenerationChunk(contentDelta: 'anthropic-正文'),
  );

  ProtocolRoutingChatGenerationClient get router =>
      ProtocolRoutingChatGenerationClient(
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

ChatGenerationRequest _request(LlmApiProtocol protocol) {
  return ChatGenerationRequest(
    target: ChatGenerationRequestTarget(
      protocol: protocol,
      endpoint: 'https://api.example.com/v1',
      apiKey: 'sk-test-12345678',
      model: 'test-model',
    ),
    messages: const [
      ChatRequestMessage(role: ChatMessageRole.user, content: '你好'),
    ],
  );
}

/// 记录型假客户端：实现三种具体客户端之一，记录收到的请求，
/// 产出固定 chunk，并可注入失败。
class _SpyClient extends ChatGenerationClient
    implements ChatCompletionsClient, ResponsesClient, AnthropicMessagesClient {
  _SpyClient({required this.protocol, required this.emittedChunk});

  final LlmApiProtocol protocol;
  final ChatGenerationChunk emittedChunk;
  final List<ChatGenerationRequest> requests = [];
  final List<Object> failures = [];

  @override
  Stream<ChatGenerationChunk> streamCompletion(
    ChatGenerationRequest request,
  ) async* {
    requests.add(request);
    for (final failure in failures) {
      throw failure;
    }
    yield emittedChunk;
  }
}
