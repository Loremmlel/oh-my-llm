import 'dart:convert';

/// 应用持久化 JSON 对象的便捷别名。
typedef JsonMap = Map<String, dynamic>;

/// 用于已版本化对象列表的 JSON 编解码工具。
final class VersionedJsonStorage {
  const VersionedJsonStorage._();

  static const int currentSchemaVersion = 1;

  /// 将对象列表编码为当前版本化 JSON 包裹结构。
  static String encodeObjectList<T>({
    required List<T> items,
    required JsonMap Function(T item) toJson,
  }) {
    return jsonEncode({
      'version': currentSchemaVersion,
      'items': items.map(toJson).toList(growable: false),
    });
  }

  /// 将单个对象编码为当前版本的 JSON 包装结构。
  static String encodeObject({required JsonMap value}) {
    return jsonEncode({'version': currentSchemaVersion, 'value': value});
  }

  /// 解析单个对象包裹，并兼容历史裸对象格式。
  static JsonMap decodeObject({
    required String rawJson,
    required String subject,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw FormatException('Stored $subject payload must be a JSON object.');
    }

    final object = Map<String, dynamic>.from(decoded);
    if (!object.containsKey('value')) {
      return object;
    }

    final version = object['version'];
    if (version is! int) {
      throw FormatException(
        'Stored $subject payload version must be an integer.',
      );
    }
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Stored $subject payload version $version is not supported.',
      );
    }

    final value = object['value'];
    if (value is! Map) {
      throw FormatException('Stored $subject payload value must be an object.');
    }
    return Map<String, dynamic>.from(value);
  }

  /// 解析版本化对象包裹。
  static List<JsonMap> decodeObjectList({
    required String rawJson,
    required String subject,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw FormatException(
        'Stored $subject payload must be a versioned object.',
      );
    }

    final version = decoded['version'];
    if (version != null && version is! int) {
      throw FormatException(
        'Stored $subject payload version must be an integer.',
      );
    }
    if (version is int && version > currentSchemaVersion) {
      throw FormatException(
        'Stored $subject payload version $version is not supported.',
      );
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw FormatException('Stored $subject payload items must be a list.');
    }

    return _decodeItems(rawItems, subject: subject);
  }

  /// 将解码后的列表归一化为强类型 JSON Map。
  static List<JsonMap> _decodeItems(
    List<dynamic> items, {
    required String subject,
  }) {
    return items
        .map((item) {
          if (item is! Map) {
            throw FormatException(
              'Stored $subject payload entries must be JSON objects.',
            );
          }

          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }
}
