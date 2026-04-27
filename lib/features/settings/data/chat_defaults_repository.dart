import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/chat_defaults.dart';

const String chatDefaultsStorageKey = 'settings.chat_defaults';

/// 聊天默认项的 SharedPreferences 仓库。
final chatDefaultsRepositoryProvider = Provider<ChatDefaultsRepository>((ref) {
  return ChatDefaultsRepository(ref.watch(sharedPreferencesProvider));
});

/// 读取和保存聊天默认项配置。
class ChatDefaultsRepository {
  const ChatDefaultsRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 读取默认模型和默认 Prompt 模板。
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

  /// 保存当前默认项配置。
  Future<void> save(ChatDefaults defaults) async {
    await _sharedPreferences.setString(
      chatDefaultsStorageKey,
      jsonEncode(defaults.toJson()),
    );
  }
}
