import 'package:shared_preferences/shared_preferences.dart';

import 'chat_conversation_repository.dart';
import 'shared_preferences_chat_conversation_repository.dart';

/// 将旧 SharedPreferences 聊天记录一次性迁移到 SQLite。
///
/// 迁移逻辑：
/// 1. 若迁移标志已置位，检查 SP 中是否还有残留旧数据并清除后直接返回。
/// 2. 若 SQLite 中已有数据（例如由其他设备同步或手动恢复），跳过导入，只清理 SP。
/// 3. 若 SP 中有旧数据，将其写入 SQLite，然后删除 SP 键并置位标志。
/// 4. 若 SP 中没有旧数据（全新安装），直接置位标志。
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
    // 迁移已完成——清除可能残留的旧 SP 数据后返回。
    if (hasLegacyPayload && repository.loadAll().isNotEmpty) {
      await preferences.remove(chatConversationsStorageKey);
    }
    return;
  }

  // SQLite 中已有数据时跳过导入（避免重复写入）。
  final existingConversations = repository.loadAll();
  if (existingConversations.isNotEmpty) {
    if (hasLegacyPayload) {
      await preferences.remove(chatConversationsStorageKey);
    }
    await preferences.setBool(chatConversationsSqliteMigrationFlagKey, true);
    return;
  }

  // 将 SP 旧数据导入 SQLite。
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
