import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/chat_conversation.dart';
import 'chat_conversation_repository.dart';

/// 基于 SharedPreferences 的旧版会话读取器，仅用于兼容迁移。
class SharedPreferencesChatConversationRepository {
  const SharedPreferencesChatConversationRepository(this._preferences);

  final SharedPreferences _preferences;

  /// 从 SharedPreferences 读取全部聊天记录。
  ///
  /// 读取时兼容旧格式（裸 JSON 数组）和新格式（`{"version":1,"items":[...]}`）。
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
}
