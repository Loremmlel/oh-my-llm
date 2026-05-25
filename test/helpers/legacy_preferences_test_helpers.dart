import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';

/// 向 SharedPreferences 写入旧版 JSON 集合数据，供迁移测试使用。
Future<void> saveLegacyPreferenceCollectionForTest<T>({
  required SharedPreferences preferences,
  required String storageKey,
  required List<T> items,
  required Map<String, dynamic> Function(T item) toJson,
}) async {
  final rawJson = VersionedJsonStorage.encodeObjectList(
    items: items,
    toJson: toJson,
  );
  await preferences.setString(storageKey, rawJson);
}
