import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/features/settings/application/preferences/settings_tab_preferences.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/settings_tab.dart';

final class _Store implements SettingsKeyValueStore {
  final ints = <String, int>{};
  final strings = <String, String>{};

  @override
  String? getString(String key) => strings[key];

  @override
  int? getInt(String key) => ints[key];

  @override
  Future<bool> setInt(String key, int value) async {
    ints[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    strings[key] = value;
    return true;
  }
}

void main() {
  group('SettingsTabPreferences', () {
    test('migrates v1 tab index and persists current version', () async {
      final store = _Store()
        ..ints[settingsLastTabIndexKey] = 3
        ..ints[settingsTabVersionKey] = 1;
      final preferences = SettingsTabPreferences(store);

      expect(await preferences.loadInitialIndex(tabCount: 6), 5);
      expect(store.ints[settingsTabVersionKey], settingsCurrentTabVersion);
      expect(store.ints[settingsLastTabIndexKey], 5);
    });

    test('未持久化顺序时返回默认顺序', () {
      final store = _Store();
      final preferences = SettingsTabPreferences(store);

      expect(preferences.initialOrder(), SettingsTab.defaultOrder);
    });

    test('持久化与读取自定义页签顺序', () async {
      final store = _Store();
      final preferences = SettingsTabPreferences(store);

      final customOrder = [
        SettingsTab.worldBooks,
        SettingsTab.network,
        SettingsTab.providers,
        SettingsTab.presets,
        SettingsTab.prompts,
        SettingsTab.outputProcessing,
        SettingsTab.other,
      ];

      await preferences.saveOrder(customOrder);
      expect(store.strings[settingsTabOrderKey], isNotNull);
      expect(preferences.initialOrder(), customOrder);
      expect(await preferences.loadOrder(), customOrder);
    });

    test('存储数据损坏时回退到默认顺序', () {
      final store = _Store()..strings[settingsTabOrderKey] = 'not-a-json';
      final preferences = SettingsTabPreferences(store);

      expect(preferences.initialOrder(), SettingsTab.defaultOrder);
    });

    test('存储遗漏部分页签时自动补齐缺失项', () {
      final store = _Store()
        ..strings[settingsTabOrderKey] = '["world_books", "network"]';
      final preferences = SettingsTabPreferences(store);

      final order = preferences.initialOrder();
      expect(order.first, SettingsTab.worldBooks);
      expect(order[1], SettingsTab.network);
      expect(order.length, SettingsTab.defaultOrder.length);
    });
  });

  group('SettingsTabOrderController', () {
    test('通过控制器重新排序页签并持久化写入', () async {
      final store = _Store();
      final container = ProviderContainer(
        overrides: [settingsKeyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final initial = container.read(settingsTabOrderProvider);
      expect(initial, SettingsTab.defaultOrder);

      // 把第 0 个项（服务商）移动到第 2 个位置
      await container.read(settingsTabOrderProvider.notifier).reorder(0, 2);

      final updated = container.read(settingsTabOrderProvider);
      expect(updated[0], SettingsTab.presets);
      expect(updated[1], SettingsTab.prompts);
      expect(updated[2], SettingsTab.providers);

      // 验证存储层也已同步写入
      final persisted = SettingsTabPreferences(store).initialOrder();
      expect(persisted, updated);

      // 重置回默认
      await container.read(settingsTabOrderProvider.notifier).resetToDefault();
      expect(
        container.read(settingsTabOrderProvider),
        SettingsTab.defaultOrder,
      );
    });
  });
}
