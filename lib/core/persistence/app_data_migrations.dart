import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chat/data/chat_conversation_migration.dart';
import '../../features/chat/data/sqlite_chat_conversation_repository.dart';
import '../../features/settings/data/fixed_prompt_sequence_migration.dart';
import '../../features/settings/data/prompt_template_migration.dart';
import '../../features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import '../../features/settings/data/sqlite_prompt_template_repository.dart';
import 'app_database.dart';

/// 执行应用启动时需要保留的一次性旧数据迁移。
Future<void> runAppDataMigrations({
  required SharedPreferences preferences,
  required AppDatabase database,
}) async {
  await migrateLegacyChatConversations(
    preferences: preferences,
    repository: SqliteChatConversationRepository(database),
  );
  await migrateLegacyPromptTemplates(
    preferences: preferences,
    repository: SqlitePromptTemplateRepository(database),
  );
  await migrateLegacyFixedPromptSequences(
    preferences: preferences,
    repository: SqliteFixedPromptSequenceRepository(database),
  );
}
