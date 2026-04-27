import 'package:shared_preferences/shared_preferences.dart';

import 'prompt_template_repository.dart';

/// SharedPreferences 中 Prompt 模板已完成 SQLite 迁移的标志键。
const String promptTemplatesSqliteMigrationFlagKey =
    'settings.prompt_templates_sqlite_migrated';

/// 将旧 SharedPreferences Prompt 模板一次性迁移到 SQLite。
///
/// 迁移逻辑：
/// 1. 若迁移标志已置位，检查 SP 中是否还有残留旧数据并清除后直接返回。
/// 2. 若 SQLite 中已有数据（例如由其他设备同步或手动恢复），跳过导入，只清理 SP。
/// 3. 若 SP 中有旧数据，将其写入 SQLite，然后删除 SP 键并置位标志。
/// 4. 若 SP 中没有旧数据（全新安装），直接置位标志。
Future<void> migrateLegacyPromptTemplates({
  required SharedPreferences preferences,
  required SqlitePromptTemplateRepository repository,
}) async {
  final hasMigrated =
      preferences.getBool(promptTemplatesSqliteMigrationFlagKey) ?? false;
  final hasLegacyPayload =
      preferences.getString(promptTemplatesStorageKey)?.trim().isNotEmpty ??
      false;

  if (hasMigrated) {
    // 迁移已完成——清除可能残留的旧 SP 数据后返回。
    if (hasLegacyPayload) {
      await preferences.remove(promptTemplatesStorageKey);
    }
    return;
  }

  // SQLite 中已有数据时跳过导入（避免重复写入）。
  final existingTemplates = repository.loadAll();
  if (existingTemplates.isNotEmpty) {
    if (hasLegacyPayload) {
      await preferences.remove(promptTemplatesStorageKey);
    }
    await preferences.setBool(promptTemplatesSqliteMigrationFlagKey, true);
    return;
  }

  // 将 SP 旧数据导入 SQLite。
  if (hasLegacyPayload) {
    final legacyTemplates = LegacyPromptTemplateRepository(
      preferences,
    ).loadAll();
    if (legacyTemplates.isNotEmpty) {
      await repository.saveAll(legacyTemplates);
    }
    await preferences.remove(promptTemplatesStorageKey);
  }

  await preferences.setBool(promptTemplatesSqliteMigrationFlagKey, true);
}
