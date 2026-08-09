import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';

void main() {
  const resolver = LlmEndpointResolver();

  group('resolveGenerationEndpoint', () {
    const cases = <(String, LlmApiProtocol, String)>[
      // 域名根地址
      (
        'https://api.openai.com',
        LlmApiProtocol.chatCompletions,
        'https://api.openai.com/v1/chat/completions',
      ),
      // 以 /v1 结尾
      (
        'https://api.openai.com/v1',
        LlmApiProtocol.responses,
        'https://api.openai.com/v1/responses',
      ),
      (
        'https://api.openai.com/v1/models',
        LlmApiProtocol.responses,
        'https://api.openai.com/v1/responses',
      ),
      // 三种完整端点原样使用
      (
        'https://api.openai.com/v1/chat/completions',
        LlmApiProtocol.chatCompletions,
        'https://api.openai.com/v1/chat/completions',
      ),
      (
        'https://api.openai.com/v1/responses',
        LlmApiProtocol.responses,
        'https://api.openai.com/v1/responses',
      ),
      (
        'https://api.openai.com/v1/messages',
        LlmApiProtocol.anthropic,
        'https://api.openai.com/v1/messages',
      ),
      // 已知端点互相替换
      (
        'https://api.openai.com/v1/chat/completions',
        LlmApiProtocol.responses,
        'https://api.openai.com/v1/responses',
      ),
      (
        'https://api.openai.com/v1/messages',
        LlmApiProtocol.chatCompletions,
        'https://api.openai.com/v1/chat/completions',
      ),
      (
        'https://api.openai.com/v1/responses',
        LlmApiProtocol.anthropic,
        'https://api.openai.com/v1/messages',
      ),
      (
        'https://host/proxy/openai/v1/chat/completions',
        LlmApiProtocol.anthropic,
        'https://host/proxy/openai/v1/messages',
      ),
      // 自定义反向代理前缀
      (
        'https://host/proxy/openai/v1',
        LlmApiProtocol.responses,
        'https://host/proxy/openai/v1/responses',
      ),
      (
        'https://host/gateway/openai',
        LlmApiProtocol.chatCompletions,
        'https://host/gateway/openai/v1/chat/completions',
      ),
      // 末尾斜杠
      (
        'https://api.openai.com/',
        LlmApiProtocol.chatCompletions,
        'https://api.openai.com/v1/chat/completions',
      ),
      (
        'https://api.openai.com/v1/',
        LlmApiProtocol.responses,
        'https://api.openai.com/v1/responses',
      ),
      (
        'https://host/proxy/openai/v1/',
        LlmApiProtocol.anthropic,
        'https://host/proxy/openai/v1/messages',
      ),
      // 已是完整后缀且带末尾斜杠时原样保留
      (
        'https://api.openai.com/v1/chat/completions/',
        LlmApiProtocol.chatCompletions,
        'https://api.openai.com/v1/chat/completions/',
      ),
      // host port
      (
        'https://host:8080',
        LlmApiProtocol.chatCompletions,
        'https://host:8080/v1/chat/completions',
      ),
      (
        'http://localhost:11434/v1',
        LlmApiProtocol.chatCompletions,
        'http://localhost:11434/v1/chat/completions',
      ),
      // query 保留
      (
        'https://host/v1?api-version=2024-01',
        LlmApiProtocol.chatCompletions,
        'https://host/v1/chat/completions?api-version=2024-01',
      ),
      (
        'https://host/v1/chat/completions?key=a&k=b',
        LlmApiProtocol.chatCompletions,
        'https://host/v1/chat/completions?key=a&k=b',
      ),
      (
        'https://host?q=1',
        LlmApiProtocol.responses,
        'https://host/v1/responses?q=1',
      ),
    ];

    for (final (input, protocol, expected) in cases) {
      test('$input + ${protocol.displayName} -> $expected', () {
        expect(
          resolver
              .resolveGenerationEndpoint(rawUrl: input, protocol: protocol)
              .toString(),
          expected,
        );
      });
    }
  });

  group('resolveApiRoot', () {
    const cases = <(String, String)>[
      ('https://api.openai.com', 'https://api.openai.com/v1'),
      ('https://api.openai.com/v1/', 'https://api.openai.com/v1'),
      (
        'https://api.openai.com/v1/chat/completions',
        'https://api.openai.com/v1',
      ),
      ('https://api.openai.com/v1/responses', 'https://api.openai.com/v1'),
      ('https://api.openai.com/v1/messages', 'https://api.openai.com/v1'),
      ('https://api.openai.com/v1/models', 'https://api.openai.com/v1'),
      (
        'https://host:8443/gateway/team-a?q=1',
        'https://host:8443/gateway/team-a/v1?q=1',
      ),
      ('  https://api.openai.com/v1  ', 'https://api.openai.com/v1'),
    ];

    for (final (input, expected) in cases) {
      test('$input -> $expected', () {
        expect(resolver.resolveApiRoot(input).toString(), expected);
      });
    }
  });

  group('resolveModelsEndpoint', () {
    const cases = <(String, String)>[
      // 域名根地址
      ('https://api.openai.com', 'https://api.openai.com/v1/models'),
      ('https://api.openai.com/', 'https://api.openai.com/v1/models'),
      // 以 /v1 结尾
      ('https://api.openai.com/v1', 'https://api.openai.com/v1/models'),
      // 三种完整生成端点先移除后缀再替换为 /models
      (
        'https://api.openai.com/v1/chat/completions',
        'https://api.openai.com/v1/models',
      ),
      (
        'https://api.openai.com/v1/responses',
        'https://api.openai.com/v1/models',
      ),
      (
        'https://api.openai.com/v1/messages',
        'https://api.openai.com/v1/models',
      ),
      (
        'https://api.openai.com/v1/chat/completions/',
        'https://api.openai.com/v1/models',
      ),
      // 已是模型列表端点：原样返回（含末尾斜杠）
      ('https://host/v1/models', 'https://host/v1/models'),
      ('https://host/v1/models/', 'https://host/v1/models/'),
      (
        'https://host/proxy/openai/v1/models',
        'https://host/proxy/openai/v1/models',
      ),
      // 自定义反向代理前缀
      ('https://host/proxy/openai/v1', 'https://host/proxy/openai/v1/models'),
      ('https://host/proxy/openai', 'https://host/proxy/openai/v1/models'),
      // host port + query 保留
      (
        'https://host:8443/proxy/openai/v1/chat/completions?q=1',
        'https://host:8443/proxy/openai/v1/models?q=1',
      ),
    ];

    for (final (input, expected) in cases) {
      test('$input -> $expected', () {
        expect(resolver.resolveModelsEndpoint(input).toString(), expected);
      });
    }
  });

  group('配置校验', () {
    const invalidUrls = <String>[
      'api.openai.com',
      '/v1/chat/completions',
      'ftp://host/v1',
      'file:///tmp/api',
      'https:///v1',
      'https://host/v1#section',
      'https://host/v1/chat/completions#frag',
    ];

    for (final input in invalidUrls) {
      test('生成端点拒绝：$input', () {
        expect(
          () => resolver.resolveGenerationEndpoint(
            rawUrl: input,
            protocol: LlmApiProtocol.chatCompletions,
          ),
          throwsA(isA<LlmEndpointResolverException>()),
        );
      });

      test('模型列表端点拒绝：$input', () {
        expect(
          () => resolver.resolveModelsEndpoint(input),
          throwsA(isA<LlmEndpointResolverException>()),
        );
      });
    }

    test('异常消息说明拒绝原因', () {
      expect(
        () => resolver.resolveGenerationEndpoint(
          rawUrl: 'https://host/v1#frag',
          protocol: LlmApiProtocol.chatCompletions,
        ),
        throwsA(
          predicate(
            (e) =>
                e is LlmEndpointResolverException &&
                e.message.contains('fragment'),
          ),
        ),
      );
      expect(
        () => resolver.resolveModelsEndpoint('ftp://host/v1'),
        throwsA(
          predicate(
            (e) =>
                e is LlmEndpointResolverException && e.message.contains('http'),
          ),
        ),
      );
    });
  });
}
