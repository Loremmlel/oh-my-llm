import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/llm_model_config_repository.dart';
import '../domain/models/llm_model_config.dart';
import '../domain/models/llm_provider_config.dart';

final llmProviderConfigsProvider =
    NotifierProvider<LlmProviderConfigsController, List<LlmProviderConfig>>(
      LlmProviderConfigsController.new,
    );

final llmModelConfigsProvider = Provider<List<LlmModelConfig>>((ref) {
  return ref
      .watch(llmProviderConfigsProvider)
      .expand((provider) => provider.resolvedModels)
      .toList(growable: false);
});

/// 服务商配置控制器，负责列表加载、增删改和排序。
class LlmProviderConfigsController extends Notifier<List<LlmProviderConfig>> {
  LlmModelConfigRepository get _repository =>
      ref.read(llmModelConfigRepositoryProvider);

  @override
  List<LlmProviderConfig> build() {
    return _repository.loadProviders();
  }

  /// 新增或更新一个服务商。
  Future<void> upsertProvider(LlmProviderConfig provider) async {
    final providers = [...state];
    final existingIndex = providers.indexWhere((item) => item.id == provider.id);
    if (existingIndex == -1) {
      providers.add(provider);
    } else {
      providers[existingIndex] = provider;
    }
    state = sortProviderConfigs(providers);
    await _repository.saveProviders(state);
  }

  /// 批量新增或更新多个服务商。
  Future<void> upsertAllProviders(List<LlmProviderConfig> providers) async {
    final updated = [...state];
    for (final provider in providers) {
      final index = updated.indexWhere((item) => item.id == provider.id);
      if (index == -1) {
        updated.add(provider);
      } else {
        updated[index] = provider;
      }
    }
    state = sortProviderConfigs(updated);
    await _repository.saveProviders(state);
  }

  /// 导入服务商配置；遇到同 URL / Key 的服务商时，合并其下新模型。
  Future<void> mergeImportedProviders(List<LlmProviderConfig> providers) async {
    final updated = [...state];
    for (final incomingProvider in providers) {
      final existingIndex = updated.indexWhere((provider) {
        return provider.apiUrl == incomingProvider.apiUrl &&
            provider.apiKey == incomingProvider.apiKey;
      });
      if (existingIndex == -1) {
        updated.add(incomingProvider);
        continue;
      }

      final existingProvider = updated[existingIndex];
      final mergedModels = [...existingProvider.models];
      for (final incomingModel in incomingProvider.models) {
        final alreadyExists = mergedModels.any((model) {
          return model.modelName == incomingModel.modelName;
        });
        if (!alreadyExists) {
          mergedModels.add(incomingModel);
        }
      }
      updated[existingIndex] = existingProvider.copyWith(models: mergedModels);
    }
    state = sortProviderConfigs(updated);
    await _repository.saveProviders(state);
  }

  /// 删除一个服务商及其下所有模型。
  Future<void> deleteProviderById(String providerId) async {
    state = state
        .where((provider) => provider.id != providerId)
        .toList(growable: false);
    await _repository.saveProviders(state);
  }

  /// 在指定服务商下新增或更新模型。
  Future<void> upsertModel({
    required String providerId,
    required LlmProviderModelConfig model,
  }) async {
    final providers = [...state];
    final providerIndex = providers.indexWhere((item) => item.id == providerId);
    if (providerIndex == -1) {
      return;
    }

    final provider = providers[providerIndex];
    final models = [...provider.models];
    final modelIndex = models.indexWhere((item) => item.id == model.id);
    if (modelIndex == -1) {
      models.add(model);
    } else {
      models[modelIndex] = model;
    }
    providers[providerIndex] = provider.copyWith(models: models);
    state = sortProviderConfigs(providers);
    await _repository.saveProviders(state);
  }

  /// 删除服务商下的单个模型。
  Future<void> deleteModel({
    required String providerId,
    required String modelId,
  }) async {
    final providers = [...state];
    final providerIndex = providers.indexWhere((item) => item.id == providerId);
    if (providerIndex == -1) {
      return;
    }

    final provider = providers[providerIndex];
    providers[providerIndex] = provider.copyWith(
      models: provider.models
          .where((model) => model.id != modelId)
          .toList(growable: false),
    );
    state = sortProviderConfigs(providers);
    await _repository.saveProviders(state);
  }
}
