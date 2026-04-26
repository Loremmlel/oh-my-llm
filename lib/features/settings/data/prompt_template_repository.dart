import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/prompt_template.dart';

const String promptTemplatesStorageKey = 'settings.prompt_templates';

final promptTemplateRepositoryProvider = Provider<PromptTemplateRepository>((
  ref,
) {
  return PromptTemplateRepository(ref.watch(sharedPreferencesProvider));
});

class PromptTemplateRepository {
  const PromptTemplateRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  List<PromptTemplate> loadAll() {
    final rawJson = _sharedPreferences.getString(promptTemplatesStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      throw const FormatException(
        'Stored prompt templates must be a JSON array.',
      );
    }

    return decoded.map((item) {
      if (item is! Map) {
        throw const FormatException(
          'Each stored prompt template must be a JSON object.',
        );
      }

      return PromptTemplate.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
  }

  Future<void> saveAll(List<PromptTemplate> templates) async {
    final rawJson = jsonEncode(
      templates.map((template) => template.toJson()).toList(growable: false),
    );
    await _sharedPreferences.setString(promptTemplatesStorageKey, rawJson);
  }
}
