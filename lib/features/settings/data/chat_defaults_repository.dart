import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/chat_defaults.dart';

const String chatDefaultsStorageKey = 'settings.chat_defaults';

/// 聊天页最近一次选择记忆的 SharedPreferences 仓库。
final chatDefaultsRepositoryProvider = Provider<ChatDefaultsRepository>((ref) {
  return ChatDefaultsRepository(ref.watch(sharedPreferencesProvider));
});

/// 读取和保存聊天页最近一次选择的模型 / 前置 Prompt。
class ChatDefaultsRepository {
  const ChatDefaultsRepository(this._sharedPreferences);

  final SharedPreferences _sharedPreferences;

  /// 读取最近一次使用的模型和前置 Prompt 模板。
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

  /// 保存当前最近一次选择记忆。
  Future<void> save(ChatDefaults defaults) async {
    await _sharedPreferences.setString(
      chatDefaultsStorageKey,
      jsonEncode(defaults.toJson()),
    );
  }
}
