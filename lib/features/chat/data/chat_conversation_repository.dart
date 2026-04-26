import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
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

    final decoded = jsonDecode(rawValue);
    if (decoded is! List) {
      throw const FormatException('Stored conversations payload must be a list.');
    }

    return decoded.map((item) {
      if (item is! Map) {
        throw const FormatException(
          'Stored conversation payload entries must be objects.',
        );
      }

      return ChatConversation.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
  }

  Future<void> saveAll(List<ChatConversation> conversations) {
    final payload = jsonEncode(
      conversations.map((conversation) => conversation.toJson()).toList(),
    );
    return _preferences.setString(chatConversationsStorageKey, payload);
  }
}
