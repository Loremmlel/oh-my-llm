import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/llm_model_config.dart';

const String llmModelConfigsStorageKey = 'settings.llm_model_configs';

final llmModelConfigRepositoryProvider = Provider<LlmModelConfigRepository>((
  ref,
) {
  return LlmModelConfigRepository(ref.watch(sharedPreferencesProvider));
});

class LlmModelConfigRepository {
  const LlmModelConfigRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  List<LlmModelConfig> loadAll() {
    final rawJson = _sharedPreferences.getString(llmModelConfigsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const [];
    }

    return VersionedJsonStorage.decodeObjectList(
          rawJson: rawJson,
          subject: 'model configs',
        )
        .map(LlmModelConfig.fromJson)
        .toList(growable: false);
  }

  Future<void> saveAll(List<LlmModelConfig> configs) async {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: configs,
      toJson: (config) => config.toJson(),
    );
    await _sharedPreferences.setString(llmModelConfigsStorageKey, rawJson);
  }
}
