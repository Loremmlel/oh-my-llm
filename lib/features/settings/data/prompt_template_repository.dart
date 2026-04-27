import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/prompt_template.dart';
import 'sqlite_prompt_template_repository.dart';

export 'sqlite_prompt_template_repository.dart'
    show SqlitePromptTemplateRepository, promptTemplateRepositoryProvider;

/// SharedPreferences 中旧版 Prompt 模板数据的键名，仅供迁移时使用。
const String promptTemplatesStorageKey = 'settings.prompt_templates';

/// 旧版 SharedPreferences Prompt 模板仓库，仅供一次性数据迁移使用。
///
/// 正式读写请使用 [promptTemplateRepositoryProvider] 对应的
/// [SqlitePromptTemplateRepository]。
class LegacyPromptTemplateRepository {
  const LegacyPromptTemplateRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 从 SharedPreferences 读取旧版全部 Prompt 模板。
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
}

/// 仅供测试使用：通过 SharedPreferences 保存 Prompt 模板（用于迁移路径测试）。
///
/// 生产代码不应调用此方法，数据写入应通过 [SqlitePromptTemplateRepository.saveAll]。
@visibleForTesting
Future<void> saveLegacyPromptTemplatesForTest(
  SharedPreferences preferences,
  List<PromptTemplate> templates,
) async {
  final rawJson = VersionedJsonStorage.encodeObjectList(
    items: templates,
    toJson: (t) => t.toJson(),
  );
  await preferences.setString(promptTemplatesStorageKey, rawJson);
}

