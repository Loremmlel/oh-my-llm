import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/versioned_json_storage.dart';

void main() {
  group('object envelope', () {
    test('encodes and decodes a current versioned object', () {
      final encoded = VersionedJsonStorage.encodeObject(
        value: {'bodyFontSize': 18},
      );

      expect(
        VersionedJsonStorage.decodeObject(
          rawJson: encoded,
          subject: 'font size settings',
        ),
        {'bodyFontSize': 18},
      );
    });

    test('拒绝无版本化包裹的历史裸对象', () {
      expect(
        () => VersionedJsonStorage.decodeObject(
          rawJson: '{"bodyFontSize":18}',
          subject: 'font size settings',
        ),
        throwsFormatException,
      );
    });

    const rejectionCases = <(String, Object)>[
      ('版本非整数', {'version': 'v1', 'value': <String, dynamic>{}}),
      (
        '未来版本',
        {
          'version': VersionedJsonStorage.currentSchemaVersion + 1,
          'value': <String, dynamic>{},
        },
      ),
      ('value 不是对象', {'version': 1, 'value': 'not-an-object'}),
      ('缺少 value 字段', {'version': 1}),
      ('JSON 顶层不是对象', 'plain string'),
      (
        'JSON 顶层是数组',
        [
          {'bodyFontSize': 18},
        ],
      ),
    ];

    for (final (name, payload) in rejectionCases) {
      test('拒绝 $name', () {
        expect(
          () => VersionedJsonStorage.decodeObject(
            rawJson: jsonEncode(payload),
            subject: 'font size settings',
          ),
          throwsFormatException,
        );
      });
    }

    test('拒绝非法 JSON 字符串', () {
      expect(
        () => VersionedJsonStorage.decodeObject(
          rawJson: '{broken json',
          subject: 'font size settings',
        ),
        throwsFormatException,
      );
    });

    // ── version 边界契约 ─────────────

    test('接受非未来版本边界', () {
      for (final version in [0, -1]) {
        final decoded = VersionedJsonStorage.decodeObject(
          rawJson: jsonEncode({
            'version': version,
            'value': {'bodyFontSize': 18},
          }),
          subject: 'font size settings',
        );
        expect(decoded['bodyFontSize'], 18, reason: 'version=$version');
      }
    });
  });

  group('decodeObjectList', () {
    test(
      'supports current versioned format with empty and populated items',
      () {
        const cases = <(String, List<Map<String, String>>)>[
          ('empty', []),
          (
            'populated',
            [
              {'id': 'item-a'},
              {'id': 'item-b'},
            ],
          ),
        ];

        for (final (name, items) in cases) {
          final decoded = VersionedJsonStorage.decodeObjectList(
            rawJson: jsonEncode({
              'version': VersionedJsonStorage.currentSchemaVersion,
              'items': items,
            }),
            subject: 'test items',
          );
          expect(decoded, items, reason: name);
        }
      },
    );

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
      (
        'items containing non-map entries',
        {
          'version': 1,
          'items': [null],
        },
      ),
      ('non-object JSON', 'plain string'),
      (
        'plain array JSON',
        [
          {'id': 'item-1'},
        ],
      ),
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

    test('accepts non-future version bounds', () {
      for (final version in [0, -1]) {
        final decoded = VersionedJsonStorage.decodeObjectList(
          rawJson: jsonEncode({
            'version': version,
            'items': [
              {'id': 'a'},
            ],
          }),
          subject: 'test items',
        );
        expect(decoded.single['id'], 'a', reason: 'version=$version');
      }
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
      expect(decoded['items'], [
        {'id': 'x'},
      ]);
    });
  });
}
