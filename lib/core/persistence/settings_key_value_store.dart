import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

/// 设置持久化所需的最小键值读写契约。
abstract interface class SettingsKeyValueStore {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  int? getInt(String key);

  Future<bool> setInt(String key, int value);
}

/// [SharedPreferences] 的设置键值适配器。
final class SharedPreferencesSettingsKeyValueStore
    implements SettingsKeyValueStore {
  const SharedPreferencesSettingsKeyValueStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  Future<bool> setInt(String key, int value) => _preferences.setInt(key, value);
}

/// 从启动时注入的 SharedPreferences 派生设置键值适配器。
final settingsKeyValueStoreProvider = Provider<SettingsKeyValueStore>((ref) {
  return SharedPreferencesSettingsKeyValueStore(
    ref.watch(sharedPreferencesProvider),
  );
});
