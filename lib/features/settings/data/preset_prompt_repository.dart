import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/legacy_preferences_json_storage.dart';
import '../domain/models/preset_prompt.dart';
import 'sqlite_preset_prompt_repository.dart';

export 'sqlite_preset_prompt_repository.dart'
    show presetPromptRepository, presetPromptRepositoryProvider;

/// SharedPreferences 中旧版 Prompt 模板数据的键名，仅供迁移时使用。
const String presetPromptsStorageKey = 'settings.preset_prompts';

/// 旧版 SharedPreferences Prompt 模板仓库，仅供一次性数据迁移使用。
///
/// 正式读写请使用 [presetPromptRepositoryProvider] 对应的
/// [SqliteEntityRepository]。
class LegacyPresetPromptRepository {
  const LegacyPresetPromptRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 从 SharedPreferences 读取旧版全部 Prompt 模板。
  List<PresetPrompt> loadAll() {
    return loadLegacyPreferenceCollection(
      preferences: _sharedPreferences,
      storageKey: presetPromptsStorageKey,
      subject: 'prompt templates',
      fromJson: PresetPrompt.fromJson,
    );
  }
}

/// 仅供测试使用：通过 SharedPreferences 保存 Prompt 模板（用于迁移路径测试）。
///
/// 生产代码不应调用此方法，数据写入应通过 [SqliteEntityRepository.saveAll]。
@visibleForTesting
Future<void> saveLegacyPresetPromptsForTest(
  SharedPreferences preferences,
  List<PresetPrompt> templates,
) async {
  await saveLegacyPreferenceCollectionForTest(
    preferences: preferences,
    storageKey: presetPromptsStorageKey,
    items: templates,
    toJson: (template) => template.toJson(),
  );
}
