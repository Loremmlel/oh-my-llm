import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/persistence/legacy_preferences_collection_migrator.dart';
import '../../../core/persistence/sqlite_entity_repository.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import 'fixed_prompt_sequence_repository.dart';

const String fixedPromptSequencesSqliteMigrationFlagKey =
    'settings.fixed_prompt_sequences_sqlite_migrated';

Future<void> migrateLegacyFixedPromptSequences({
  required SharedPreferences preferences,
  required SqliteEntityRepository<FixedPromptSequence> repository,
  required AppDatabase database,
}) async {
  await LegacyPreferencesCollectionMigrator<FixedPromptSequence>(
    preferences: preferences,
    migrationFlagKey: fixedPromptSequencesSqliteMigrationFlagKey,
    legacyStorageKey: fixedPromptSequencesStorageKey,
    loadCurrentItems: () => repository.loadAll(database),
    loadLegacyItems:
        LegacyFixedPromptSequenceRepository(preferences).loadAll,
    saveCurrentItems: (items) => repository.saveAll(database, items),
  ).migrate();
}
