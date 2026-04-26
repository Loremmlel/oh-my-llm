import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
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

    return VersionedJsonStorage.decodeObjectList(
      rawJson: rawJson,
      subject: 'prompt templates',
    ).map(PromptTemplate.fromJson).toList(growable: false);
  }

  Future<void> saveAll(List<PromptTemplate> templates) async {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: templates,
      toJson: (template) => template.toJson(),
    );
    await _sharedPreferences.setString(promptTemplatesStorageKey, rawJson);
  }
}
