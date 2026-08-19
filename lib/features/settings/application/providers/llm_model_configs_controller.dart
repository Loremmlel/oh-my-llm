import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/llm_model_config_repository.dart';
import '../../domain/models/providers/llm_model_config.dart';
import '../../domain/models/providers/llm_provider_config.dart';
import 'llm_provider_import_merger.dart' hide sortProviderConfigs;

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
    final existingIndex = providers.indexWhere(
      (item) => item.id == provider.id,
    );
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

  /// 导入服务商配置；遇到同 ID 或同等价键的服务商时，合并其下新模型。
  ///
  /// 匹配优先级：
  /// 1. **ID 匹配**：同一实体在不同设备上 URL 可能不同但 ID 相同，
  ///    此时用传入服务商的字段（name、apiUrl、apiKey）覆盖本地，合并模型。
  /// 2. **协议+API root+Key 匹配**：不同设备各自创建的同凭据服务商，
  ///    保留本地服务商身份，仅合并模型。
  /// 3. **无匹配**：作为新服务商添加。
  Future<void> mergeImportedProviders(List<LlmProviderConfig> providers) async {
    final nextState = mergeImportedLlmProviders(
      local: state,
      incoming: providers,
    );
    await replaceAllAfterImport(nextState);
  }

  /// 导入流程在持久化确认后替换内存快照。
  Future<void> replaceAllAfterImport(List<LlmProviderConfig> providers) async {
    final nextState = sortProviderConfigs(providers);
    await _repository.saveProviders(nextState);
    state = nextState;
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

  /// 在指定服务商下批量新增模型，跳过已存在同 modelName 的模型。
  ///
  /// 返回实际新增的模型数量（跳过重复项后的净增量）。
  Future<int> upsertModels({
    required String providerId,
    required List<LlmProviderModelConfig> models,
  }) async {
    if (models.isEmpty) {
      return 0;
    }

    final providers = [...state];
    final providerIndex = providers.indexWhere((item) => item.id == providerId);
    if (providerIndex == -1) {
      return 0;
    }

    final provider = providers[providerIndex];
    final existingModelNames = provider.models
        .map((model) => model.modelName)
        .toSet();
    final mergedModels = [...provider.models];
    for (final model in models) {
      if (!existingModelNames.contains(model.modelName)) {
        mergedModels.add(model);
        existingModelNames.add(model.modelName);
      }
    }
    providers[providerIndex] = provider.copyWith(models: mergedModels);
    state = sortProviderConfigs(providers);
    await _repository.saveProviders(state);
    return mergedModels.length - provider.models.length;
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
