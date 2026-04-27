import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/chat_conversation.dart';
import 'chat_conversation_repository.dart';

/// 基于 SharedPreferences 的旧版会话持久化仓库，仅用于兼容迁移。
class SharedPreferencesChatConversationRepository
    implements ChatConversationRepository {
  const SharedPreferencesChatConversationRepository(this._preferences);

  final SharedPreferences _preferences;

  @override
  List<ChatConversation> loadAll() {
    final rawValue = _preferences.getString(chatConversationsStorageKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const [];
    }

    return VersionedJsonStorage.decodeObjectList(
      rawJson: rawValue,
      subject: 'conversations',
    ).map(ChatConversation.fromJson).toList(growable: false);
  }

  @override
  Future<void> saveAll(List<ChatConversation> conversations) {
    final payload = VersionedJsonStorage.encodeObjectList(
      items: conversations,
      toJson: (conversation) => conversation.toJson(),
    );
    return _preferences.setString(chatConversationsStorageKey, payload);
  }
}
