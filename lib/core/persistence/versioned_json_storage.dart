import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

final class VersionedJsonStorage {
  const VersionedJsonStorage._();

  static const int currentSchemaVersion = 1;

  static String encodeObjectList<T>({
    required List<T> items,
    required JsonMap Function(T item) toJson,
  }) {
    return jsonEncode({
      'version': currentSchemaVersion,
      'items': items.map(toJson).toList(growable: false),
    });
  }

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
      throw FormatException('Stored $subject payload version must be an integer.');
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

  static List<JsonMap> _decodeItems(List<dynamic> items, {required String subject}) {
    return items.map((item) {
      if (item is! Map) {
        throw FormatException(
          'Stored $subject payload entries must be JSON objects.',
        );
      }

      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
  }
}
