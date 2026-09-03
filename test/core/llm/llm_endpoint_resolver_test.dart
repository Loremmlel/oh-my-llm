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
      // 版本段识别：API 根以 /vN 结尾（如火山方舟 /api/v3、智谱 /api/paas/v4）
      // 时不再补 /v1，直接拼协议末段
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3',
        LlmApiProtocol.responses,
        'https://ark.cn-beijing.volces.com/api/coding/v3/responses',
      ),
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3',
        LlmApiProtocol.chatCompletions,
        'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions',
      ),
      (
        'https://open.bigmodel.cn/api/paas/v4',
        LlmApiProtocol.chatCompletions,
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      ),
      // 终端段匹配：完整端点原样使用，不额外补 /v1
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3/responses',
        LlmApiProtocol.responses,
        'https://ark.cn-beijing.volces.com/api/coding/v3/responses',
      ),
      (
        'https://api.perplexity.ai/chat/completions',
        LlmApiProtocol.chatCompletions,
        'https://api.perplexity.ai/chat/completions',
      ),
      // 已知端点相互替换（非 /v1 版本段根）
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions',
        LlmApiProtocol.responses,
        'https://ark.cn-beijing.volces.com/api/coding/v3/responses',
      ),
    ];

    test('生成端点表覆盖协议、代理前缀、版本段和查询参数', () {
      for (final (input, protocol, expected) in cases) {
        expect(
          resolver
              .resolveGenerationEndpoint(rawUrl: input, protocol: protocol)
              .toString(),
          expected,
          reason: '$input + ${protocol.displayName}',
        );
      }
    });
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
      // 版本段识别：非 /v1 根保持原样
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3',
        'https://ark.cn-beijing.volces.com/api/coding/v3',
      ),
      // 终端段剥离后仍识别版本段
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3/responses',
        'https://ark.cn-beijing.volces.com/api/coding/v3',
      ),
      // 边界：版本段在中间（Gemini /v1beta/openai）时末段非 /vN，仍按代理前缀补 /v1
      (
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        'https://generativelanguage.googleapis.com/v1beta/openai/v1',
      ),
    ];

    test('API 根地址表覆盖端点剥离、版本段与代理前缀', () {
      for (final (input, expected) in cases) {
        expect(
          resolver.resolveApiRoot(input).toString(),
          expected,
          reason: input,
        );
      }
    });
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
      // 版本段识别：非 /v1 根
      (
        'https://ark.cn-beijing.volces.com/api/coding/v3',
        'https://ark.cn-beijing.volces.com/api/coding/v3/models',
      ),
    ];

    test('模型端点表覆盖完整端点、代理前缀和查询参数', () {
      for (final (input, expected) in cases) {
        expect(
          resolver.resolveModelsEndpoint(input).toString(),
          expected,
          reason: input,
        );
      }
    });
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

    test('生成端点与模型端点拒绝非法配置', () {
      for (final input in invalidUrls) {
        expect(
          () => resolver.resolveGenerationEndpoint(
            rawUrl: input,
            protocol: LlmApiProtocol.chatCompletions,
          ),
          throwsA(isA<LlmEndpointResolverException>()),
          reason: '生成端点：$input',
        );
        expect(
          () => resolver.resolveModelsEndpoint(input),
          throwsA(isA<LlmEndpointResolverException>()),
          reason: '模型端点：$input',
        );
      }
    });

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
