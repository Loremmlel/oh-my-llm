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
        : migrateLegacyModelsToProviders(
            items.map((item) => LlmModelConfig.fromJson(item)),
          );
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
    return loadProviders()
        .expand((provider) => provider.resolvedModels)
        .toList(growable: false);
  }

  List<LlmProviderConfig> _sortProviders(List<LlmProviderConfig> providers) {
    final normalized =
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
    return List.unmodifiable(normalized);
  }
}
