import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/legacy_preferences_collection_migrator.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import 'fixed_prompt_sequence_repository.dart';

/// SharedPreferences 中固定顺序提示词已完成 SQLite 迁移的标志键。
const String fixedPromptSequencesSqliteMigrationFlagKey =
    'settings.fixed_prompt_sequences_sqlite_migrated';

/// 将旧 SharedPreferences 固定顺序提示词序列一次性迁移到 SQLite。
///
/// 迁移逻辑：
/// 1. 若迁移标志已置位，检查 SP 中是否还有残留旧数据并清除后直接返回。
/// 2. 若 SQLite 中已有数据，跳过导入，只清理 SP。
/// 3. 若 SP 中有旧数据，将其写入 SQLite，然后删除 SP 键并置位标志。
/// 4. 若 SP 中没有旧数据（全新安装），直接置位标志。
Future<void> migrateLegacyFixedPromptSequences({
  required SharedPreferences preferences,
  required SqliteFixedPromptSequenceRepository repository,
}) async {
  await LegacyPreferencesCollectionMigrator<FixedPromptSequence>(
    preferences: preferences,
    migrationFlagKey: fixedPromptSequencesSqliteMigrationFlagKey,
    legacyStorageKey: fixedPromptSequencesStorageKey,
    loadCurrentItems: repository.loadAll,
    loadLegacyItems: LegacyFixedPromptSequenceRepository(preferences).loadAll,
    saveCurrentItems: repository.saveAll,
  ).migrate();
}
