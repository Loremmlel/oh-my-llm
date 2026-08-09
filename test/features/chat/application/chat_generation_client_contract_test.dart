import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  group('ChatGenerationRequestTarget', () {
    test('协议中立目标原样携带原始 endpoint 与鉴权字段', () {
      const target = ChatGenerationRequestTarget(
        protocol: LlmApiProtocol.anthropic,
        endpoint: 'https://api.anthropic.com',
        apiKey: 'sk-anthropic',
        model: 'claude-sonnet',
      );
      expect(target.protocol, LlmApiProtocol.anthropic);
      expect(target.endpoint, 'https://api.anthropic.com');
      expect(target.apiKey, 'sk-anthropic');
      expect(target.model, 'claude-sonnet');
    });

    test('Equatable：字段相同则相等，字段不同则不等', () {
      const base = ChatGenerationRequestTarget(
        protocol: LlmApiProtocol.chatCompletions,
        endpoint: 'https://api.example.com',
        apiKey: 'key',
        model: 'model-a',
      );
      expect(
        base,
        equals(
          const ChatGenerationRequestTarget(
            protocol: LlmApiProtocol.chatCompletions,
            endpoint: 'https://api.example.com',
            apiKey: 'key',
            model: 'model-a',
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatGenerationRequestTarget(
              protocol: LlmApiProtocol.responses,
              endpoint: 'https://api.example.com',
              apiKey: 'key',
              model: 'model-a',
            ),
          ),
        ),
      );
    });
  });

  group('ChatGenerationRequest', () {
    test('构造携带 target/messages 与可选参数', () {
      final request = ChatGenerationRequest(
        target: const ChatGenerationRequestTarget(
          protocol: LlmApiProtocol.chatCompletions,
          endpoint: 'https://api.example.com',
          apiKey: 'key',
          model: 'gpt-4.1',
        ),
        messages: const [
          ChatRequestMessage(role: ChatMessageRole.user, content: '你好'),
        ],
        reasoningEffort: ReasoningEffort.low,
        streamIdleTimeout: const Duration(seconds: 30),
      );

      expect(request.target.model, 'gpt-4.1');
      expect(request.messages.single.role, ChatMessageRole.user);
      expect(request.messages.single.content, '你好');
      expect(request.reasoningEffort, ReasoningEffort.low);
      expect(request.streamIdleTimeout, const Duration(seconds: 30));
    });

    test('可选参数默认 null', () {
      final request = ChatGenerationRequest(
        target: const ChatGenerationRequestTarget(
          protocol: LlmApiProtocol.chatCompletions,
          endpoint: 'https://api.example.com',
          apiKey: 'key',
          model: 'gpt-4.1',
        ),
        messages: const [],
      );

      expect(request.reasoningEffort, isNull);
      expect(request.streamIdleTimeout, isNull);
    });
  });

  group('ChatGenerationUsage', () {
    test('默认构造全部字段为 null', () {
      const usage = ChatGenerationUsage();

      expect(usage.inputTokens, isNull);
      expect(usage.outputTokens, isNull);
      expect(usage.reasoningTokens, isNull);
      expect(usage.cachedInputTokens, isNull);
    });

    test('填充字段原样保留', () {
      const usage = ChatGenerationUsage(
        inputTokens: 10,
        outputTokens: 20,
        reasoningTokens: 5,
        cachedInputTokens: 3,
      );

      expect(usage.inputTokens, 10);
      expect(usage.outputTokens, 20);
      expect(usage.reasoningTokens, 5);
      expect(usage.cachedInputTokens, 3);
    });

    test('Equatable：字段相同则相等，字段不同则不等', () {
      const a = ChatGenerationUsage(inputTokens: 1, outputTokens: 2);
      const b = ChatGenerationUsage(inputTokens: 1, outputTokens: 2);
      const c = ChatGenerationUsage(inputTokens: 1, outputTokens: 3);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('merge：新值覆盖旧值，新值缺失时保留旧值', () {
      const previous = ChatGenerationUsage(
        inputTokens: 10,
        outputTokens: 20,
        cachedInputTokens: 3,
      );
      const newer = ChatGenerationUsage(inputTokens: 11, reasoningTokens: 5);

      expect(
        previous.merge(newer),
        const ChatGenerationUsage(
          inputTokens: 11,
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 3,
        ),
      );
    });
  });

  group('ChatGenerationClient.complete', () {
    test('折叠正文、推理、最后一个 finish reason 与分散 usage', () async {
      final client = _ChunkSequenceClient([
        const ChatGenerationChunk(
          contentDelta: '正',
          usage: ChatGenerationUsage(inputTokens: 10, cachedInputTokens: 3),
        ),
        const ChatGenerationChunk(
          reasoningDelta: '思考',
          finishReason: 'length',
          usage: ChatGenerationUsage(outputTokens: 20, reasoningTokens: 5),
        ),
        const ChatGenerationChunk(contentDelta: '文', finishReason: 'stop'),
      ]);

      final result = await client.complete(
        ChatGenerationRequest(
          target: const ChatGenerationRequestTarget(
            protocol: LlmApiProtocol.chatCompletions,
            endpoint: 'https://api.example.com',
            apiKey: 'key',
            model: 'model',
          ),
          messages: const [],
        ),
      );

      expect(result.content, '正文');
      expect(result.reasoningContent, '思考');
      expect(result.finishReason, 'stop');
      expect(
        result.usage,
        const ChatGenerationUsage(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 3,
        ),
      );
    });
  });

  group('ChatGenerationException', () {
    test('携带 protocol/uri/apiErrorCode 等新字段', () {
      final exception = ChatGenerationException(
        '请求失败（429）',
        protocol: LlmApiProtocol.chatCompletions,
        uri: Uri.parse('https://api.example.com/v1/chat/completions'),
        statusCode: 429,
        apiErrorCode: 'rate_limit_exceeded',
        responseBody: '{"error":{"code":"rate_limit_exceeded"}}',
        cause: StateError('原始异常'),
        causeStackTrace: StackTrace.empty,
      );

      expect(exception.message, '请求失败（429）');
      expect(exception.protocol, LlmApiProtocol.chatCompletions);
      expect(
        exception.uri,
        Uri.parse('https://api.example.com/v1/chat/completions'),
      );
      expect(exception.statusCode, 429);
      expect(exception.apiErrorCode, 'rate_limit_exceeded');
      expect(
        exception.responseBody,
        '{"error":{"code":"rate_limit_exceeded"}}',
      );
      expect(exception.cause, isA<StateError>());
      expect(exception.causeStackTrace, StackTrace.empty);
    });

    test('新字段默认 null，toString 返回 message', () {
      const exception = ChatGenerationException('boom');

      expect(exception.protocol, isNull);
      expect(exception.uri, isNull);
      expect(exception.statusCode, isNull);
      expect(exception.apiErrorCode, isNull);
      expect(exception.responseBody, isNull);
      expect(exception.cause, isNull);
      expect(exception.causeStackTrace, isNull);
      expect(exception.toString(), 'boom');
    });
  });
}

final class _ChunkSequenceClient extends ChatGenerationClient {
  _ChunkSequenceClient(this.chunks);

  final List<ChatGenerationChunk> chunks;

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request) {
    return Stream.fromIterable(chunks);
  }
}
