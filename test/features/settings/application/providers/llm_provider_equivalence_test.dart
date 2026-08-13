import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_provider_equivalence.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

void main() {
  LlmProviderConfig provider({
    String apiUrl = 'https://api.example.com',
    String apiKey = 'key',
    LlmApiProtocol apiProtocol = LlmApiProtocol.chatCompletions,
  }) {
    return LlmProviderConfig(
      id: 'provider',
      name: 'Provider',
      apiUrl: apiUrl,
      apiKey: apiKey,
      apiProtocol: apiProtocol,
    );
  }

  test('域名、v1 根和完整端点为同一服务商等价键', () {
    final keys = [
      provider(apiUrl: 'https://api.example.com'),
      provider(apiUrl: 'https://api.example.com/v1'),
      provider(apiUrl: 'https://api.example.com/v1/chat/completions'),
    ].map(buildLlmProviderEquivalenceKey).toSet();

    expect(keys, hasLength(1));
  });

  test('协议、query 或 key 不同时等价键不同', () {
    final base = buildLlmProviderEquivalenceKey(provider());
    final variants = [
      provider(apiProtocol: LlmApiProtocol.responses),
      provider(apiUrl: 'https://api.example.com?tenant=b'),
      provider(apiKey: 'other-key'),
    ].map(buildLlmProviderEquivalenceKey);

    for (final variant in variants) {
      expect(variant, isNot(base));
    }
  });

  test('无效历史 URL 使用 trim 后原值作为稳定回退', () {
    final first = buildLlmProviderEquivalenceKey(
      provider(apiUrl: '  invalid url  '),
    );
    final second = buildLlmProviderEquivalenceKey(
      provider(apiUrl: 'invalid url'),
    );

    expect(first, second);
    expect(first.apiRoot, 'invalid url');
  });
}
