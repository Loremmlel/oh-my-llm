import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';

void main() {
  group('decodeObjectList', () {
    test('supports current versioned format with empty items', () {
      final decoded = VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode({
          'version': VersionedJsonStorage.currentSchemaVersion,
          'items': <dynamic>[],
        }),
        subject: 'test items',
      );
      expect(decoded, isEmpty);
    });

    test('supports current versioned format with items', () {
      final decoded = VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode({
          'version': VersionedJsonStorage.currentSchemaVersion,
          'items': [
            {'id': 'item-a'},
            {'id': 'item-b'},
          ],
        }),
        subject: 'test items',
      );
      expect(decoded, hasLength(2));
      expect(decoded.first['id'], 'item-a');
    });

    test('rejects unsupported future versions', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode({
            'version': VersionedJsonStorage.currentSchemaVersion + 1,
            'items': const [],
          }),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-integer version', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode({
            'version': 'v1',
            'items': const [],
          }),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-list items', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode({
            'version': 1,
            'items': 'not-a-list',
          }),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects items containing non-map entries', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode({
            'version': 1,
            'items': [null],
          }),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-object JSON', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode('plain string'),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects plain array JSON', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode([
            {'id': 'item-1'},
          ]),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    test('rejects invalid JSON string', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: '{broken json',
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });
  });

  group('encodeObjectList', () {
    test('encodes items with current version', () {
      final encoded = VersionedJsonStorage.encodeObjectList(
        items: [
          {'id': 'x'},
        ],
        toJson: (item) => item,
      );
      final decoded = jsonDecode(encoded) as Map;
      expect(decoded['version'], VersionedJsonStorage.currentSchemaVersion);
      expect(decoded['items'], [{'id': 'x'}]);
    });

    test('encodes empty list', () {
      final encoded = VersionedJsonStorage.encodeObjectList(
        items: <Map<String, dynamic>>[],
        toJson: (item) => item,
      );
      final decoded = jsonDecode(encoded) as Map;
      expect(decoded['items'], isEmpty);
    });
  });
}
