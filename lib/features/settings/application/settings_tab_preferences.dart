import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_key_value_store.dart';

const settingsLastTabIndexKey = 'settings.tab.last_index';
const settingsTabVersionKey = 'settings.tab.version';
const settingsCurrentTabVersion = 4;

/// 设置页标签索引的版本迁移与持久化。
final class SettingsTabPreferences {
  const SettingsTabPreferences(this._store);

  final SettingsKeyValueStore _store;

  /// 同步读取启动所需的索引，避免设置页先显示错误标签再异步跳转。
  int initialIndex({required int tabCount}) {
    final savedVersion = _store.getInt(settingsTabVersionKey) ?? 1;
    final index = _store.getInt(settingsLastTabIndexKey) ?? 0;
    return _resolveIndex(
      savedIndex: index,
      savedVersion: savedVersion,
      tabCount: tabCount,
    );
  }

  Future<int> loadInitialIndex({required int tabCount}) async {
    final savedVersion = _store.getInt(settingsTabVersionKey) ?? 1;
    final savedIndex = _store.getInt(settingsLastTabIndexKey) ?? 0;
    final index = _resolveIndex(
      savedIndex: savedIndex,
      savedVersion: savedVersion,
      tabCount: tabCount,
    );
    if (savedVersion < settingsCurrentTabVersion) {
      await _saveMigratedIndex(index);
    }
    return index;
  }

  Future<void> saveIndex(int index) async {
    final didPersist = await _store.setInt(settingsLastTabIndexKey, index);
    if (!didPersist) throw StateError('Failed to persist settings tab index.');
  }

  Future<void> _saveMigratedIndex(int index) async {
    final indexSaved = await _store.setInt(settingsLastTabIndexKey, index);
    final versionSaved = await _store.setInt(
      settingsTabVersionKey,
      settingsCurrentTabVersion,
    );
    if (!indexSaved || !versionSaved) {
      throw StateError('Failed to migrate settings tab preference.');
    }
  }

  int _migrate(int savedIndex, int savedVersion) {
    var index = savedIndex;
    if (savedVersion < 2) {
      if (index == 3) {
        index = 4;
      } else if (index == 4) {
        index = 3;
      }
    }
    if (savedVersion < 4) {
      if (index == 4) {
        index = 5;
      } else if (index == 5) {
        index = 4;
      }
    }
    return index;
  }

  int _resolveIndex({
    required int savedIndex,
    required int savedVersion,
    required int tabCount,
  }) {
    final migrated = savedVersion < settingsCurrentTabVersion
        ? _migrate(savedIndex, savedVersion)
        : savedIndex;
    return migrated.clamp(0, tabCount - 1);
  }
}

final settingsTabPreferencesProvider = Provider<SettingsTabPreferences>((ref) {
  return SettingsTabPreferences(ref.watch(settingsKeyValueStoreProvider));
});
