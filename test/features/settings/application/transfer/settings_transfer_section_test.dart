import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_section.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';

void main() {
  group('SettingsTransferSection 元数据', () {
    for (final invalidKey in [
      '',
      'Pascal',
      'with_underscore',
      'with-hyphen',
      '中文',
    ]) {
      test('拒绝非法 key「$invalidKey」', () {
        expect(
          () => _replaceSection(key: invalidKey),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('拒绝空白 label', () {
      expect(
        () => _replaceSection(key: 'validKey', label: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Coordinator 拒绝重复 key', () {
      expect(
        () => SettingsTransferCoordinator(
          sections: [
            _replaceSection(key: 'sameKey'),
            _replaceSection(key: 'sameKey'),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Coordinator 只投影已有分组并聚合敏感性', () {
      final coordinator = SettingsTransferCoordinator(
        sections: [
          _replaceSection(
            key: 'standardSetting',
            group: SettingsTransferGroup.other,
          ),
          _replaceSection(
            key: 'sensitiveSetting',
            group: SettingsTransferGroup.providers,
            sensitivity: SettingsTransferSensitivity.credentialBearing,
          ),
        ],
      );

      expect(coordinator.groups.map((item) => item.wireKey), [
        'providers',
        'other',
      ]);
      expect(coordinator.groups.first.containsSensitive, isTrue);
      expect(coordinator.groups.last.containsSensitive, isFalse);
    });
  });

  group('SettingsTransferSection 策略', () {
    test('replacing 对非等价值生成替换或清空变化', () {
      var local = '原值';
      final section = SettingsTransferSection.replacing<String>(
        key: 'replaceValue',
        group: SettingsTransferGroup.other,
        label: '替换值',
        order: 0,
        sensitivity: SettingsTransferSensitivity.standard,
        readLocal: () => local,
        write: (value) async => local = value,
        encode: (value) => {'value': value},
        decode: (payload) => payload['value']! as String,
        isEmpty: (value) => value.isEmpty,
      );

      expect(section.prepareImport('原值'), isNull);
      final replace = section.prepareImport('新值')!;
      expect(replace.summary.action, SettingsTransferSummaryAction.replace);
      final clear = section.prepareImport('')!;
      expect(clear.summary.action, SettingsTransferSummaryAction.clear);
    });

    test('merging 只保留本地和同批次都不存在的项目', () async {
      var local = [_Item(1)];
      final section = SettingsTransferSection.merging<_Item>(
        key: 'mergeItems',
        group: SettingsTransferGroup.prompts,
        label: '合并项目',
        order: 0,
        sensitivity: SettingsTransferSensitivity.standard,
        readLocal: () => local,
        write: (value) async => local = value,
        encodeItem: (value) => {'id': value.id},
        decodeItem: (payload) => _Item(payload['id']! as int),
        isEquivalent: (left, right) => left.id == right.id,
      );

      final decoded = section.decodePayload([
        {'id': 1},
        {'id': 2},
        {'id': 2},
      ]);
      final change = section.prepareImport(decoded)!;

      expect(change.summary.count, 1);
      await section.applyImport(change);
      expect(local.map((item) => item.id), [2]);
    });

    test('merging 会在 prepare 前校验每个解码项目', () {
      final section = SettingsTransferSection.merging<_Item>(
        key: 'validatedItems',
        group: SettingsTransferGroup.prompts,
        label: '校验项目',
        order: 0,
        sensitivity: SettingsTransferSensitivity.standard,
        readLocal: () => const [],
        write: (_) async {},
        encodeItem: (value) => {'id': value.id},
        decodeItem: (payload) => _Item(payload['id']! as int),
        isEquivalent: (left, right) => left.id == right.id,
        validateItem: (value) {
          if (value.id < 0) throw const FormatException('id 无效');
        },
      );

      expect(
        () => section.decodePayload([
          {'id': -1},
        ]),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

SettingsTransferSection _replaceSection({
  required String key,
  String label = '设置',
  SettingsTransferGroup group = SettingsTransferGroup.other,
  SettingsTransferSensitivity sensitivity =
      SettingsTransferSensitivity.standard,
}) => SettingsTransferSection.replacing<int>(
  key: key,
  group: group,
  label: label,
  order: 0,
  sensitivity: sensitivity,
  readLocal: () => 1,
  write: (_) async {},
  encode: (value) => {'value': value},
  decode: (payload) => payload['value']! as int,
);

final class _Item {
  const _Item(this.id);

  final int id;
}
