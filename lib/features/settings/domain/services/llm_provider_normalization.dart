import '../models/providers/llm_provider_config.dart';

/// 对服务商列表及其下属模型按名称排序，返回不可变列表。
List<LlmProviderConfig> sortProviderConfigs(List<LlmProviderConfig> providers) {
  final sorted =
      providers
          .map((provider) {
            final models = [...provider.models]
              ..sort((left, right) {
                return left.displayName.toLowerCase().compareTo(
                  right.displayName.toLowerCase(),
                );
              });
            return provider.copyWith(models: List.unmodifiable(models));
          })
          .toList(growable: false)
        ..sort((left, right) {
          return left.name.toLowerCase().compareTo(right.name.toLowerCase());
        });
  return List.unmodifiable(sorted);
}
