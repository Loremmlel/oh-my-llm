import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../core/persistence/versioned_json_storage.dart';
import '../domain/models/chat_conversation.dart';

const chatConversationsStorageKey = 'chat_conversations';

final chatConversationRepositoryProvider = Provider<ChatConversationRepository>((
  ref,
) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return ChatConversationRepository(preferences);
});

class ChatConversationRepository {
  const ChatConversationRepository(this._preferences);

  final SharedPreferences _preferences;

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

  Future<void> saveAll(List<ChatConversation> conversations) {
    final payload = VersionedJsonStorage.encodeObjectList(
      items: conversations,
      toJson: (conversation) => conversation.toJson(),
    );
    return _preferences.setString(chatConversationsStorageKey, payload);
  }
}
