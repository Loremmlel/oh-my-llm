import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_migration.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/settings/data/fixed_prompt_sequence_migration.dart';
import 'package:oh_my_llm/features/settings/data/prompt_template_migration.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';

/// 创建测试用内存数据库，并按正式启动流程执行全部数据迁移。
Future<AppDatabase> createTestDatabase(SharedPreferences preferences) async {
  final database = AppDatabase.inMemory();
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
  return database;
}
