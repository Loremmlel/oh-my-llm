import 'package:shared_preferences/shared_preferences.dart';

import 'versioned_json_storage.dart';

/// 从 SharedPreferences 读取旧版 JSON 集合数据，并按指定解析器转为强类型列表。
List<T> loadLegacyPreferenceCollection<T>({
  required SharedPreferences preferences,
  required String storageKey,
  required String subject,
  required T Function(Map<String, dynamic> json) fromJson,
}) {
  final rawJson = preferences.getString(storageKey);
  if (rawJson == null || rawJson.trim().isEmpty) {
    return const [];
  }

  return VersionedJsonStorage.decodeObjectList(
    rawJson: rawJson,
    subject: subject,
  ).map(fromJson).toList(growable: false);
}
