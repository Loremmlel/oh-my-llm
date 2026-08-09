import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';

import '../domain/models/llm_provider_config.dart';

typedef LlmProviderEquivalenceKey = ({
  LlmApiProtocol apiProtocol,
  String apiRoot,
  String apiKey,
});

/// 构建导入合并使用的服务商等价键。
///
/// 无效历史 URL 保留 trim 后原值，避免导入流程崩溃或把不同坏配置误合并。
LlmProviderEquivalenceKey buildLlmProviderEquivalenceKey(
  LlmProviderConfig provider, {
  LlmEndpointResolver resolver = const LlmEndpointResolver(),
}) {
  String apiRoot;
  try {
    apiRoot = resolver.resolveApiRoot(provider.apiUrl).toString();
  } on LlmEndpointResolverException {
    apiRoot = provider.apiUrl.trim();
  }
  return (
    apiProtocol: provider.apiProtocol,
    apiRoot: apiRoot,
    apiKey: provider.apiKey,
  );
}
