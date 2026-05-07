import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/legacy_preferences_collection_migrator.dart';
import '../domain/models/prompt_template.dart';
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
  await LegacyPreferencesCollectionMigrator<PromptTemplate>(
    preferences: preferences,
    migrationFlagKey: promptTemplatesSqliteMigrationFlagKey,
    legacyStorageKey: promptTemplatesStorageKey,
    loadCurrentItems: repository.loadAll,
    loadLegacyItems: LegacyPromptTemplateRepository(preferences).loadAll,
    saveCurrentItems: repository.saveAll,
  ).migrate();
}
