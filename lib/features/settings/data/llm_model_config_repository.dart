import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/llm_model_config.dart';
import '../domain/models/llm_provider_config.dart';

const String llmModelConfigsStorageKey = 'settings.llm_model_configs';

/// 服务商配置的 SharedPreferences 仓库。
final llmModelConfigRepositoryProvider = Provider<LlmModelConfigRepository>((
  ref,
) {
  return LlmModelConfigRepository(ref.watch(sharedPreferencesProvider));
});

/// 读取和保存 LLM 服务商与模型配置。
class LlmModelConfigRepository {
  const LlmModelConfigRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 读取全部服务商配置，并兼容旧版平铺模型结构。
  List<LlmProviderConfig> loadProviders() {
    final rawJson = _sharedPreferences.getString(llmModelConfigsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const [];
    }

    final items = VersionedJsonStorage.decodeObjectList(
      rawJson: rawJson,
      subject: 'model providers',
    );
    if (items.isEmpty) {
      return const [];
    }

    final isProviderShape = items.any((item) => item['models'] is List);
    final providers = isProviderShape
        ? items.map(LlmProviderConfig.fromJson).toList(growable: false)
        : _migrateLegacyModels(items.map(LlmModelConfig.fromJson).toList());
    return _sortProviders(providers);
  }

  /// 保存全部服务商配置。
  Future<void> saveProviders(List<LlmProviderConfig> providers) async {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: _sortProviders(providers),
      toJson: (provider) => provider.toJson(),
    );
    await _sharedPreferences.setString(llmModelConfigsStorageKey, rawJson);
  }

  /// 读取全部展开后的模型配置，仅供聊天页与请求层使用。
  List<LlmModelConfig> loadAll() {
    return loadProviders().expand((provider) => provider.resolvedModels).toList(
      growable: false,
    );
  }

  /// 兼容旧测试与工具调用：把平铺模型列表转换并保存为服务商结构。
  Future<void> saveAll(List<LlmModelConfig> configs) async {
    await saveProviders(_providersFromResolvedModels(configs));
  }

  List<LlmProviderConfig> _migrateLegacyModels(List<LlmModelConfig> models) {
    final providers = <LlmProviderConfig>[];
    final providerIndexBySignature = <String, int>{};

    for (final model in models) {
      final signature = _buildSignature(model.apiUrl, model.apiKey);
      final existingIndex = providerIndexBySignature[signature];
      final providerModel = LlmProviderModelConfig(
        id: model.id,
        displayName: model.displayName,
        modelName: model.modelName,
        supportsReasoning: model.supportsReasoning,
      );

      if (existingIndex == null) {
        providerIndexBySignature[signature] = providers.length;
        providers.add(
          LlmProviderConfig(
            id: 'provider-${providers.length + 1}',
            name: '服务商${providers.length + 1}',
            apiUrl: model.apiUrl,
            apiKey: model.apiKey,
            models: [providerModel],
          ),
        );
        continue;
      }

      final existingProvider = providers[existingIndex];
      providers[existingIndex] = existingProvider.copyWith(
        models: [...existingProvider.models, providerModel],
      );
    }

    return providers;
  }

  List<LlmProviderConfig> _providersFromResolvedModels(
    List<LlmModelConfig> configs,
  ) {
    final providers = <LlmProviderConfig>[];
    final providerIndexByKey = <String, int>{};

    for (final config in configs) {
      final signature = config.providerId.isNotEmpty
          ? 'provider:${config.providerId}'
          : _buildSignature(config.apiUrl, config.apiKey);
      final existingIndex = providerIndexByKey[signature];
      final providerModel = LlmProviderModelConfig(
        id: config.id,
        displayName: config.displayName,
        modelName: config.modelName,
        supportsReasoning: config.supportsReasoning,
      );

      if (existingIndex == null) {
        providerIndexByKey[signature] = providers.length;
        providers.add(
          LlmProviderConfig(
            id: config.providerId.isNotEmpty
                ? config.providerId
                : 'provider-${providers.length + 1}',
            name: config.providerName.isNotEmpty
                ? config.providerName
                : '服务商${providers.length + 1}',
            apiUrl: config.apiUrl,
            apiKey: config.apiKey,
            models: [providerModel],
          ),
        );
        continue;
      }

      final existingProvider = providers[existingIndex];
      providers[existingIndex] = existingProvider.copyWith(
        models: [...existingProvider.models, providerModel],
      );
    }

    return providers;
  }

  String _buildSignature(String apiUrl, String apiKey) {
    return '${apiUrl.trim()}::${apiKey.trim()}';
  }

  List<LlmProviderConfig> _sortProviders(List<LlmProviderConfig> providers) {
    final normalized = providers
        .map((provider) {
          final models = [...provider.models]..sort((left, right) {
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
    return List.unmodifiable(normalized);
  }
}
