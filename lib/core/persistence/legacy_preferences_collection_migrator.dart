import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 旧集合数据迁移到新存储的通用模板。
final class LegacyPreferencesCollectionMigrator<T> {
  const LegacyPreferencesCollectionMigrator({
    required this.preferences,
    required this.migrationFlagKey,
    required this.legacyStorageKey,
    required this.loadCurrentItems,
    required this.loadLegacyItems,
    required this.saveCurrentItems,
    this.requireCurrentDataBeforeClearingMigratedPayload = false,
  });

  final SharedPreferences preferences;
  final String migrationFlagKey;
  final String legacyStorageKey;
  final List<T> Function() loadCurrentItems;
  final List<T> Function() loadLegacyItems;
  final Future<void> Function(List<T> items) saveCurrentItems;
  final bool requireCurrentDataBeforeClearingMigratedPayload;

  Future<void> migrate() async {
    final hasMigrated = preferences.getBool(migrationFlagKey) ?? false;
    final hasLegacyPayload =
        preferences.getString(legacyStorageKey)?.trim().isNotEmpty ?? false;

    if (hasMigrated) {
      final hasCurrentItems = loadCurrentItems().isNotEmpty;
      final shouldClearLegacyPayload =
          hasLegacyPayload &&
          (!requireCurrentDataBeforeClearingMigratedPayload || hasCurrentItems);
      if (shouldClearLegacyPayload) {
        await preferences.remove(legacyStorageKey);
      }
      return;
    }

    final existingItems = loadCurrentItems();
    if (existingItems.isNotEmpty) {
      if (hasLegacyPayload) {
        await preferences.remove(legacyStorageKey);
      }
      await preferences.setBool(migrationFlagKey, true);
      return;
    }

    if (hasLegacyPayload) {
      final legacyItems = loadLegacyItems();
      if (legacyItems.isNotEmpty) {
        await saveCurrentItems(legacyItems);
      }
      await preferences.remove(legacyStorageKey);
    }

    await preferences.setBool(migrationFlagKey, true);
  }
}
