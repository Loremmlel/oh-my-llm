import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../../core/persistence/legacy_preferences_collection_migrator.dart';
import '../../../../core/persistence/sqlite_entity_repository.dart';
import '../../domain/models/prompt_template.dart';
import '../prompt_template_repository.dart';

const String promptTemplatesSqliteMigrationFlagKey =
    'settings.prompt_templates_sqlite_migrated';

Future<void> migrateLegacyPromptTemplates({
  required SharedPreferences preferences,
  required SqliteEntityRepository<PromptTemplate> repository,
  required AppDatabase database,
}) async {
  await LegacyPreferencesCollectionMigrator<PromptTemplate>(
    preferences: preferences,
    migrationFlagKey: promptTemplatesSqliteMigrationFlagKey,
    legacyStorageKey: promptTemplatesStorageKey,
    loadCurrentItems: () => repository.loadAll(database),
    loadLegacyItems: LegacyPromptTemplateRepository(preferences).loadAll,
    saveCurrentItems: (items) => repository.saveAll(database, items),
  ).migrate();
}
