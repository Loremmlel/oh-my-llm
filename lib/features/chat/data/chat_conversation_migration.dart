import 'package:shared_preferences/shared_preferences.dart';

import 'chat_conversation_repository.dart';
import 'shared_preferences_chat_conversation_repository.dart';

/// 将旧 SharedPreferences 聊天记录迁移到 SQLite。
Future<void> migrateLegacyChatConversations({
  required SharedPreferences preferences,
  required ChatConversationRepository repository,
}) async {
  final hasMigrated =
      preferences.getBool(chatConversationsSqliteMigrationFlagKey) ?? false;
  final hasLegacyPayload =
      preferences.getString(chatConversationsStorageKey)?.trim().isNotEmpty ??
      false;
  if (hasMigrated) {
    if (hasLegacyPayload && repository.loadAll().isNotEmpty) {
      await preferences.remove(chatConversationsStorageKey);
    }
    return;
  }

  final existingConversations = repository.loadAll();
  if (existingConversations.isNotEmpty) {
    if (hasLegacyPayload) {
      await preferences.remove(chatConversationsStorageKey);
    }
    await preferences.setBool(chatConversationsSqliteMigrationFlagKey, true);
    return;
  }

  final legacyRepository = SharedPreferencesChatConversationRepository(
    preferences,
  );
  final legacyConversations = legacyRepository.loadAll();
  if (legacyConversations.isNotEmpty) {
    await repository.saveAll(legacyConversations);
    await preferences.remove(chatConversationsStorageKey);
  }

  await preferences.setBool(chatConversationsSqliteMigrationFlagKey, true);
}
