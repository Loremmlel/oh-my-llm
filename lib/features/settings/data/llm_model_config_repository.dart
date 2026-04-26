import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException('Stored model configs must be a JSON array.');
    }

    return decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'Each stored model config must be a JSON object.',
            );
          }

          return LlmModelConfig.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
  }

  Future<void> saveAll(List<LlmModelConfig> configs) async {
    final rawJson = jsonEncode(
      configs.map((config) => config.toJson()).toList(growable: false),
    );
    await _sharedPreferences.setString(llmModelConfigsStorageKey, rawJson);
  }
}
