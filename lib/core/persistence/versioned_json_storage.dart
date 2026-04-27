import 'dart:convert';

/// 应用持久化 JSON 对象的便捷别名。
typedef JsonMap = Map<String, dynamic>;

/// 用于已版本化对象列表的 JSON 编解码工具。
///
/// 该格式同时兼容当前版本化包裹结构和旧版原始数组，避免旧数据无法读取。
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

  /// 解析旧版 JSON 数组或版本化对象包裹。
  static List<JsonMap> decodeObjectList({
    required String rawJson,
    required String subject,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is List) {
      return _decodeItems(decoded, subject: subject);
    }

    if (decoded is! Map) {
      throw FormatException(
        'Stored $subject payload must be a JSON array or versioned object.',
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
