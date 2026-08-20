import '../../domain/models/providers/llm_provider_config.dart';
import '../../domain/services/llm_provider_normalization.dart';
import 'llm_provider_equivalence.dart';

/// 纯函数：按导入优先级合并服务商及其模型。
List<LlmProviderConfig> mergeImportedLlmProviders({
  required List<LlmProviderConfig> local,
  required List<LlmProviderConfig> incoming,
}) {
  final updated = [...local];

  for (final incomingProvider in incoming) {
    var existingIndex = updated.indexWhere(
      (provider) => provider.id == incomingProvider.id,
    );

    if (existingIndex != -1) {
      final existingProvider = updated[existingIndex];
      updated[existingIndex] = incomingProvider.copyWith(
        models: _mergeModels(existingProvider.models, incomingProvider.models),
      );
      continue;
    }

    final incomingKey = buildLlmProviderEquivalenceKey(incomingProvider);
    existingIndex = updated.indexWhere(
      (provider) => buildLlmProviderEquivalenceKey(provider) == incomingKey,
    );
    if (existingIndex == -1) {
      updated.add(incomingProvider);
      continue;
    }

    final existingProvider = updated[existingIndex];
    updated[existingIndex] = existingProvider.copyWith(
      models: _mergeModels(existingProvider.models, incomingProvider.models),
    );
  }

  return sortProviderConfigs(updated);
}

List<LlmProviderModelConfig> _mergeModels(
  List<LlmProviderModelConfig> local,
  List<LlmProviderModelConfig> incoming,
) {
  final merged = [...local];
  final modelNames = local.map((model) => model.modelName).toSet();
  for (final model in incoming) {
    if (modelNames.add(model.modelName)) {
      merged.add(model);
    }
  }
  return merged;
}
