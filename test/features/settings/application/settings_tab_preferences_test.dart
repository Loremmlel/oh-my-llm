import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/features/settings/application/settings_tab_preferences.dart';

final class _Store implements SettingsKeyValueStore {
  final ints = <String, int>{};
  @override
  String? getString(String key) => null;
  @override
  int? getInt(String key) => ints[key];
  @override
  Future<bool> setInt(String key, int value) async {
    ints[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async => true;
}

void main() {
  test('migrates v1 tab index and persists current version', () async {
    final store = _Store()
      ..ints[settingsLastTabIndexKey] = 3
      ..ints[settingsTabVersionKey] = 1;
    final preferences = SettingsTabPreferences(store);

    expect(await preferences.loadInitialIndex(tabCount: 6), 5);
    expect(store.ints[settingsTabVersionKey], settingsCurrentTabVersion);
    expect(store.ints[settingsLastTabIndexKey], 5);
  });
}
