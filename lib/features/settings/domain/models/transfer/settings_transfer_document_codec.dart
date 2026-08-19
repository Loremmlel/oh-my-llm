import 'dart:convert';

import 'settings_transfer_document.dart';

sealed class SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeResult();
}

final class SettingsTransferDocumentDecodeSuccess
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeSuccess(this.document);

  final SettingsTransferDocument document;
}

final class SettingsTransferDocumentUnsupportedVersion
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentUnsupportedVersion(this.version);

  final int version;
}

final class SettingsTransferDocumentMalformed
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentMalformed();
}

/// 只负责校验 Settings transfer 文档的 canonical 顶层结构。
final class SettingsTransferDocumentCodec {
  const SettingsTransferDocumentCodec._();

  static SettingsTransferDocumentDecodeResult decodeJson(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const SettingsTransferDocumentMalformed();
    }
    try {
      final decoded = jsonDecode(text);
      final object = _asStringObject(decoded);
      if (object == null) return const SettingsTransferDocumentMalformed();
      return decodeObject(object);
    } catch (_) {
      return const SettingsTransferDocumentMalformed();
    }
  }

  static SettingsTransferDocumentDecodeResult decodeObject(
    Map<String, Object?> source,
  ) {
    if (source.length != 3 ||
        !source.containsKey('identifier') ||
        !source.containsKey('formatVersion') ||
        !source.containsKey('sections')) {
      return const SettingsTransferDocumentMalformed();
    }
    if (source['identifier'] != SettingsTransferDocument.identifier) {
      return const SettingsTransferDocumentMalformed();
    }

    final version = source['formatVersion'];
    if (version is! int) return const SettingsTransferDocumentMalformed();
    if (version != SettingsTransferDocument.formatVersion) {
      return SettingsTransferDocumentUnsupportedVersion(version);
    }

    final rawSections = source['sections'];
    if (rawSections is! Map) {
      return const SettingsTransferDocumentMalformed();
    }

    final sections = <String, Object?>{};
    for (final entry in rawSections.entries) {
      final key = entry.key;
      if (key is! String || !_isValidSectionKey(key)) {
        return const SettingsTransferDocumentMalformed();
      }
      sections[key] = entry.value;
    }

    try {
      return SettingsTransferDocumentDecodeSuccess(
        SettingsTransferDocument(sections: sections),
      );
    } catch (_) {
      return const SettingsTransferDocumentMalformed();
    }
  }

  static String encodeJson(SettingsTransferDocument document) =>
      jsonEncode(document.toJson());
}

Map<String, Object?>? _asStringObject(Object? value) {
  if (value is! Map) return null;
  final object = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    object[key] = entry.value;
  }
  return object;
}

bool _isValidSectionKey(String key) =>
    RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(key);
