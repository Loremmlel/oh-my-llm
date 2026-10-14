import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';

import '../../domain/models/preferences/settings_tab.dart';

const settingsTabOrderKey = 'settings.tab.order';
const settingsLastTabIndexKey = 'settings.tab.last_index';
const settingsTabVersionKey = 'settings.tab.version';
const settingsCurrentTabVersion = 4;

/// 设置页标签索引与展示顺序的版本迁移与持久化。
final class SettingsTabPreferences {
  const SettingsTabPreferences(this._store);

  final SettingsKeyValueStore _store;

  /// 同步读取页签顺序，避免设置页初次渲染时发生顺序跳动。
  List<SettingsTab> initialOrder() {
    final raw = _store.getString(settingsTabOrderKey);
    if (raw == null || raw.isEmpty) {
      return List<SettingsTab>.of(SettingsTab.defaultOrder);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return SettingsTab.sanitizeOrder(decoded.whereType<String>());
      }
    } catch (_) {
      // 存储损坏时回退到默认顺序。
    }
    return List<SettingsTab>.of(SettingsTab.defaultOrder);
  }

  /// 异步读取页签顺序。
  Future<List<SettingsTab>> loadOrder() async {
    return initialOrder();
  }

  /// 持久化页签顺序。
  Future<void> saveOrder(List<SettingsTab> order) async {
    final sanitized = SettingsTab.sanitizeOrder(SettingsTab.toKeys(order));
    final raw = jsonEncode(SettingsTab.toKeys(sanitized));
    final didPersist = await _store.setString(settingsTabOrderKey, raw);
    if (!didPersist) {
      throw StateError('Failed to persist settings tab order.');
    }
  }

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

final settingsTabOrderProvider =
    NotifierProvider<SettingsTabOrderController, List<SettingsTab>>(
      SettingsTabOrderController.new,
    );

/// 设置页页签顺序控制器，支持拖拽重排与顺序持久化。
class SettingsTabOrderController extends Notifier<List<SettingsTab>> {
  SettingsTabPreferences get _preferences =>
      ref.read(settingsTabPreferencesProvider);

  @override
  List<SettingsTab> build() {
    return _preferences.initialOrder();
  }

  /// 调整页签顺序并持久化写入。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }
    final next = List<SettingsTab>.of(state);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    state = next;
    await _preferences.saveOrder(next);
  }

  /// 重置为默认展示顺序并持久化。
  Future<void> resetToDefault() async {
    final defaultOrder = List<SettingsTab>.of(SettingsTab.defaultOrder);
    state = defaultOrder;
    await _preferences.saveOrder(defaultOrder);
  }
}
