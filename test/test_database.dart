import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/data/chat_conversation_migration.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';

/// 创建测试用内存数据库，并按正式启动流程迁移旧聊天数据。
Future<AppDatabase> createTestDatabase(SharedPreferences preferences) async {
  final database = AppDatabase.inMemory();
  await migrateLegacyChatConversations(
    preferences: preferences,
    repository: SqliteChatConversationRepository(database),
  );
  return database;
}
