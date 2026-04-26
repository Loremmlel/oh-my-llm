import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/chat_defaults.dart';

const String chatDefaultsStorageKey = 'settings.chat_defaults';

final chatDefaultsRepositoryProvider = Provider<ChatDefaultsRepository>((ref) {
  return ChatDefaultsRepository(ref.watch(sharedPreferencesProvider));
});

class ChatDefaultsRepository {
  const ChatDefaultsRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  ChatDefaults load() {
    final rawJson = _sharedPreferences.getString(chatDefaultsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const ChatDefaults();
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException(
        'Stored chat defaults payload must be a JSON object.',
      );
    }

    return ChatDefaults.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> save(ChatDefaults defaults) async {
    await _sharedPreferences.setString(
      chatDefaultsStorageKey,
      jsonEncode(defaults.toJson()),
    );
  }
}
