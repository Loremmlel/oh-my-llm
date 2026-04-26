import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';

void main() {
  test('decodeObjectList supports legacy array payloads', () {
    final decoded = VersionedJsonStorage.decodeObjectList(
      rawJson: jsonEncode([
        {'id': 'item-1'},
      ]),
      subject: 'test items',
    );

    expect(decoded, [
      {'id': 'item-1'},
    ]);
  });

  test('encodeObjectList writes versioned payloads', () {
    final rawJson = VersionedJsonStorage.encodeObjectList(
      items: const ['item-1'],
      toJson: (item) => {'id': item},
    );

    expect(jsonDecode(rawJson), {
      'version': VersionedJsonStorage.currentSchemaVersion,
      'items': [
        {'id': 'item-1'},
      ],
    });
  });

  test('decodeObjectList rejects unsupported future versions', () {
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
}
