import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/prompt_template.dart';

const String promptTemplatesStorageKey = 'settings.prompt_templates';

/// Prompt 模板的 SharedPreferences 仓库。
final promptTemplateRepositoryProvider = Provider<PromptTemplateRepository>((
  ref,
) {
  return PromptTemplateRepository(ref.watch(sharedPreferencesProvider));
});

/// 读取和保存 Prompt 模板列表。
class PromptTemplateRepository {
  const PromptTemplateRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 读取全部 Prompt 模板。
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

  /// 保存全部 Prompt 模板。
  Future<void> saveAll(List<PromptTemplate> templates) async {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: templates,
      toJson: (template) => template.toJson(),
    );
    await _sharedPreferences.setString(promptTemplatesStorageKey, rawJson);
  }
}
