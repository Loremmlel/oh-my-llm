import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';
import '../domain/models/preferences/chat_defaults.dart';

const String chatDefaultsStorageKey = 'settings.chat_defaults';

/// 聊天页最近一次选择记忆的 SharedPreferences 仓库。
final chatDefaultsRepositoryProvider = Provider<ChatDefaultsRepository>((ref) {
  return ChatDefaultsRepository.fromStore(
    ref.watch(settingsKeyValueStoreProvider),
  );
});

/// 读取和保存聊天页最近一次选择的模型 / 前置 Prompt。
class ChatDefaultsRepository {
  ChatDefaultsRepository(SharedPreferences preferences)
    : this.fromStore(SharedPreferencesSettingsKeyValueStore(preferences));

  ChatDefaultsRepository.fromStore(SettingsKeyValueStore storage)
    : _store = VersionedJsonStore<ChatDefaults>(
        storage: storage,
        key: chatDefaultsStorageKey,
        subject: 'chat defaults',
        fallback: () => const ChatDefaults(),
        fromJson: ChatDefaults.fromJson,
        toJson: (defaults) => defaults.toJson(),
      );

  final VersionedJsonStore<ChatDefaults> _store;

  /// 读取最近一次使用的模型和前置 Prompt 模板。
  ChatDefaults load() => _store.load();

  /// 保存当前最近一次选择记忆。
  Future<void> save(ChatDefaults defaults) => _store.save(defaults);
}
