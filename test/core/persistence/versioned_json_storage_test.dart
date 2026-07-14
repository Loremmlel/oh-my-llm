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
            'items': const <dynamic>[],
          }),
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    const rejectionCases = <(String, Object)>[
      ('non-integer version', {'version': 'v1', 'items': <dynamic>[]}),
      ('non-list items', {'version': 1, 'items': 'not-a-list'}),
      ('items containing non-map entries', {'version': 1, 'items': [null]}),
      ('non-object JSON', 'plain string'),
      ('plain array JSON', [{'id': 'item-1'}]),
    ];

    for (final (name, payload) in rejectionCases) {
      test('rejects $name', () {
        expect(
          () => VersionedJsonStorage.decodeObjectList(
            rawJson: jsonEncode(payload),
            subject: 'test items',
          ),
          throwsFormatException,
        );
      });
    }

    test('rejects invalid JSON string', () {
      expect(
        () => VersionedJsonStorage.decodeObjectList(
          rawJson: '{broken json',
          subject: 'test items',
        ),
        throwsFormatException,
      );
    });

    // ── version 边界契约 ─────────────

    test('accepts missing version field', () {
      final decoded = VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode({'items': <dynamic>[]}),
        subject: 'test items',
      );
      expect(decoded, isEmpty);
    });

    test('accepts version 0', () {
      final decoded = VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode({
          'version': 0,
          'items': [
            {'id': 'a'},
          ],
        }),
        subject: 'test items',
      );
      expect(decoded, hasLength(1));
      expect(decoded.first['id'], 'a');
    });

    test('accepts negative version', () {
      final decoded = VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode({
          'version': -1,
          'items': [
            {'id': 'a'},
          ],
        }),
        subject: 'test items',
      );
      expect(decoded, hasLength(1));
      expect(decoded.first['id'], 'a');
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
