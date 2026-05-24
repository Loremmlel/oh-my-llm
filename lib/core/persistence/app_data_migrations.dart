import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chat/data/chat_conversation_migration.dart';
import '../../features/chat/data/sqlite_chat_conversation_repository.dart';
import '../../features/settings/data/migrations/fixed_prompt_sequence_migration.dart';
import '../../features/settings/data/migrations/preset_prompt_migration.dart';
import '../../features/settings/data/preset_prompt_repository.dart';
import '../../features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'app_database.dart';

Future<void> runAppDataMigrations({
  required SharedPreferences preferences,
  required AppDatabase database,
}) async {
  // 迁移旧的 SP 迁移标志到新键名，避免重复执行迁移。
  const oldFlagKey = 'settings.prompt_templates_sqlite_migrated';
  if (preferences.containsKey(oldFlagKey)) {
    final wasMigrated = preferences.getBool(oldFlagKey) ?? false;
    preferences.setBool(presetPromptsSqliteMigrationFlagKey, wasMigrated);
    preferences.remove(oldFlagKey);
  }
  // 旧数据键也需迁移，否则跳版本升级时迁移流程读不到旧数据。
  const oldDataKey = 'settings.prompt_templates';
  if (preferences.containsKey(oldDataKey)) {
    final oldData = preferences.getString(oldDataKey);
    preferences.setString(presetPromptsStorageKey, oldData ?? '');
    preferences.remove(oldDataKey);
  }

  await migrateLegacyChatConversations(
    preferences: preferences,
    repository: SqliteChatConversationRepository(database),
  );
  await migrateLegacyPresetPrompts(
    preferences: preferences,
    repository: presetPromptRepository,
    database: database,
  );
  await migrateLegacyFixedPromptSequences(
    preferences: preferences,
    repository: fixedPromptSequenceRepository,
    database: database,
  );
}
