import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../../core/persistence/legacy_preferences_collection_migrator.dart';
import '../../../../core/persistence/sqlite_entity_repository.dart';
import '../../domain/models/preset_prompt.dart';
import '../preset_prompt_repository.dart';

const String presetPromptsSqliteMigrationFlagKey =
    'settings.preset_prompts_sqlite_migrated';

Future<void> migrateLegacyPresetPrompts({
  required SharedPreferences preferences,
  required SqliteEntityRepository<PresetPrompt> repository,
  required AppDatabase database,
}) async {
  await LegacyPreferencesCollectionMigrator<PresetPrompt>(
    preferences: preferences,
    migrationFlagKey: presetPromptsSqliteMigrationFlagKey,
    legacyStorageKey: presetPromptsStorageKey,
    loadCurrentItems: () => repository.loadAll(database),
    loadLegacyItems: LegacyPresetPromptRepository(preferences).loadAll,
    saveCurrentItems: (items) => repository.saveAll(database, items),
  ).migrate();
}
