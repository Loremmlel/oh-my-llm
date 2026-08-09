import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('ChatGenerationRequestTarget', () {
    test('fromModelConfig 派生 protocol/endpoint/apiKey/model 四项', () {
      final config = TestFixtures.model(
        apiProtocol: LlmApiProtocol.anthropic,
        apiUrl: 'https://api.anthropic.com',
        apiKey: 'sk-anthropic',
        modelName: 'claude-sonnet',
      );

      final target = ChatGenerationRequestTarget.fromModelConfig(config);

      expect(target.protocol, LlmApiProtocol.anthropic);
      expect(target.endpoint, 'https://api.anthropic.com/v1/messages');
      expect(target.apiKey, 'sk-anthropic');
      expect(target.model, 'claude-sonnet');
    });

    test('fromModelConfig 将 API 根地址解析为最终生成端点（三种协议）', () {
      const cases = <(LlmApiProtocol, String, String)>[
        (
          LlmApiProtocol.chatCompletions,
          'https://api.openai.com',
          'https://api.openai.com/v1/chat/completions',
        ),
        (
          LlmApiProtocol.responses,
          'https://api.openai.com',
          'https://api.openai.com/v1/responses',
        ),
        (
          LlmApiProtocol.anthropic,
          'https://api.anthropic.com',
          'https://api.anthropic.com/v1/messages',
        ),
      ];

      for (final (protocol, apiUrl, expectedEndpoint) in cases) {
        final target = ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.model(apiUrl: apiUrl, apiProtocol: protocol),
        );
        expect(target.endpoint, expectedEndpoint, reason: protocol.name);
        expect(target.protocol, protocol, reason: protocol.name);
      }
    });

    test('fromModelConfig 对完整生成端点原样保留（resolver 幂等）', () {
      const cases = <(LlmApiProtocol, String)>[
        (
          LlmApiProtocol.chatCompletions,
          'https://api.example.com/v1/chat/completions',
        ),
        (LlmApiProtocol.responses, 'https://api.example.com/v1/responses'),
        (LlmApiProtocol.anthropic, 'https://api.example.com/v1/messages'),
      ];

      for (final (protocol, apiUrl) in cases) {
        final target = ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.model(apiUrl: apiUrl, apiProtocol: protocol),
        );
        expect(target.endpoint, apiUrl, reason: protocol.name);
      }
    });

    test('fromModelConfig 无效 URL → ChatGenerationException（protocol 填对）', () {
      expect(
        () => ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.model(
            apiUrl: 'not-a-url',
            apiProtocol: LlmApiProtocol.anthropic,
          ),
        ),
        throwsA(
          isA<ChatGenerationException>()
              .having((e) => e.protocol, 'protocol', LlmApiProtocol.anthropic)
              .having((e) => e.message, 'message', contains('not-a-url')),
        ),
      );
    });

    test('fromModelConfig 非 http(s) 协议 URL → ChatGenerationException', () {
      expect(
        () => ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.model(
            apiUrl: 'ftp://api.example.com',
            apiProtocol: LlmApiProtocol.chatCompletions,
          ),
        ),
        throwsA(
          isA<ChatGenerationException>().having(
            (e) => e.protocol,
            'protocol',
            LlmApiProtocol.chatCompletions,
          ),
        ),
      );
    });

    test('Equatable：字段相同则相等，字段不同则不等', () {
      final base = ChatGenerationRequestTarget.fromModelConfig(
        TestFixtures.gpt41(),
      );
      expect(
        base,
        equals(
          ChatGenerationRequestTarget.fromModelConfig(TestFixtures.gpt41()),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            ChatGenerationRequestTarget.fromModelConfig(
              TestFixtures.deepSeekV4(),
            ),
          ),
        ),
      );
    });
  });

  group('ChatGenerationRequest', () {
    test('构造携带 target/messages 与可选参数', () {
      final request = ChatGenerationRequest(
        target: ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.gpt41(),
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
        target: ChatGenerationRequestTarget.fromModelConfig(
          TestFixtures.gpt41(),
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
