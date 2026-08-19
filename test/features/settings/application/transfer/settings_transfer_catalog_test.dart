import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';

void main() {
  group('SettingsTransferCatalog', () {
    test('按分组顺序、participant 顺序和 key 排序', () {
      final providerLater = _FakeIntParticipant(
        key: const SettingsTransferKey('providerLater'),
        group: SettingsTransferGroup.providers,
        order: 2,
      );
      final providerEarlier = _FakeIntParticipant(
        key: const SettingsTransferKey('providerEarlier'),
        group: SettingsTransferGroup.providers,
        order: 1,
      );
      final other = _FakeIntParticipant(
        key: const SettingsTransferKey('other'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final catalog = SettingsTransferCatalog([
        _box(other),
        _box(providerLater),
        _box(providerEarlier),
      ]);

      expect(
        catalog
            .participantsForGroups({
              SettingsTransferGroup.other,
              SettingsTransferGroup.providers,
            })
            .map((participant) => participant.key.value),
        ['providerEarlier', 'providerLater', 'other'],
      );
    });

    test('拒绝重复 key', () {
      final first = _FakeIntParticipant(
        key: const SettingsTransferKey('sameKey'),
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final second = _FakeIntParticipant(
        key: const SettingsTransferKey('sameKey'),
        group: SettingsTransferGroup.other,
        order: 0,
      );

      expect(
        () => SettingsTransferCatalog([_box(first), _box(second)]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('拒绝同组重复 order', () {
      final first = _FakeIntParticipant(
        key: const SettingsTransferKey('first'),
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final second = _FakeIntParticipant(
        key: const SettingsTransferKey('second'),
        group: SettingsTransferGroup.providers,
        order: 0,
      );

      expect(
        () => SettingsTransferCatalog([_box(first), _box(second)]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('拒绝空白或不符合规则的 key 以及空白 label', () {
      final invalidKeys = ['', ' Providers', 'Providers', 'provider-key'];
      for (final value in invalidKeys) {
        expect(
          () => SettingsTransferCatalog([
            _box(
              _FakeIntParticipant(
                key: SettingsTransferKey(value),
                group: SettingsTransferGroup.providers,
                order: 0,
              ),
            ),
          ]),
          throwsA(isA<ArgumentError>()),
          reason: 'key=$value 应被拒绝',
        );
      }

      expect(
        () => SettingsTransferCatalog([
          _box(
            _FakeIntParticipant(
              key: const SettingsTransferKey('validKey'),
              group: SettingsTransferGroup.providers,
              order: 0,
              label: '  ',
            ),
          ),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('为已注册分组生成 descriptor 并聚合 credential sensitivity', () {
      final sensitive = _FakeIntParticipant(
        key: const SettingsTransferKey('sensitive'),
        group: SettingsTransferGroup.providers,
        order: 0,
        sensitivity: SettingsTransferSensitivity.credentialBearing,
      );
      final standard = _FakeIntParticipant(
        key: const SettingsTransferKey('standard'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final catalog = SettingsTransferCatalog([
        _box(sensitive),
        _box(standard),
      ]);

      expect(catalog.groups.map((descriptor) => descriptor.group), [
        SettingsTransferGroup.providers,
        SettingsTransferGroup.other,
      ]);
      expect(catalog.groups[0].wireKey, 'providers');
      expect(catalog.groups[0].label, '服务商');
      expect(catalog.groups[0].order, 0);
      expect(catalog.groups[0].containsSensitive, isTrue);
      expect(catalog.groups[1].containsSensitive, isFalse);
    });

    test('typed lookup 成功且错误类型在执行前失败', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('typedInt'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final catalog = SettingsTransferCatalog([_box(participant)]);

      expect(catalog.participant<int>(participant.key), same(participant));
      expect(
        () => catalog.participant<String>(participant.key),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('typedInt'),
          ),
        ),
      );
      expect(participant.readCount, 0);
      expect(participant.writeCount, 0);
    });

    test('测试 catalog 可以注册不依赖生产 schema 的 fake key', () {
      const key = SettingsTransferKey('testOnlyFake9');
      final participant = _FakeIntParticipant(
        key: key,
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final catalog = SettingsTransferCatalog([_box(participant)]);

      expect(catalog.groupForKey(key), SettingsTransferGroup.other);
      expect(catalog.participant<int>(key), same(participant));
    });
  });

  group('ReplacingValueParticipant', () {
    test('相同完整值不产生 change', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('replaceInt'),
        group: SettingsTransferGroup.other,
        order: 0,
      );

      expect(participant.prepareImport(local: 7, incoming: 7), isNull);
    });

    test('空 replacement 生成 clear summary', () {
      final participant = _FakeNullableStringParticipant(
        key: const SettingsTransferKey('replaceNullable'),
        group: SettingsTransferGroup.network,
        order: 0,
      );

      final change = participant.prepareImport(local: '已有值', incoming: null);

      expect(change, isNotNull);
      expect(change!.summary.action, SettingsTransferSummaryAction.clear);
      expect(change.summary.count, isNull);
      expect(change.summary.trailingText, '清空');
    });
  });

  group('MergingCollectionParticipant', () {
    test('空 local 合并两个唯一值生成一条 add change', () {
      final participant = _FakeCollectionParticipant(
        key: const SettingsTransferKey('mergeItems'),
        group: SettingsTransferGroup.prompts,
        order: 0,
      );

      final change = participant.prepareImport(
        local: const [],
        incoming: [1, 2],
      );

      expect(change, isNotNull);
      expect(change!.writeValue, [1, 2]);
      expect(change.summary.action, SettingsTransferSummaryAction.add);
      expect(change.summary.count, 2);
      expect(change.summary.trailingText, '新增 2 项');
    });

    test('本地已有内容时 writeValue 只包含新增项', () {
      final participant = _FakeCollectionParticipant(
        key: const SettingsTransferKey('mergeItems'),
        group: SettingsTransferGroup.prompts,
        order: 0,
      );

      final change = participant.prepareImport(local: [1], incoming: [1, 2]);

      expect(change, isNotNull);
      expect(change!.writeValue, [2]);
      expect(change.summary.count, 1);
      expect(change.fingerprint, '[2]');
    });

    test('空 collection 不参与导出', () {
      final participant = _FakeCollectionParticipant(
        key: const SettingsTransferKey('mergeItems'),
        group: SettingsTransferGroup.prompts,
        order: 0,
      );

      expect(participant.shouldExport(const []), isFalse);
    });
  });

  group('SettingsTransferParticipantBox', () {
    test('catalog 拒绝未经过 box 的公共 participant', () {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('unboxedDirect'),
        group: SettingsTransferGroup.other,
        order: 0,
      );

      expect(
        () => SettingsTransferCatalog([participant]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('direct participant 的 prepare 会校验返回 change 的 identity', () {
      final other = _DirectIntParticipant(
        key: const SettingsTransferKey('otherParticipant'),
        group: SettingsTransferGroup.other,
        order: 1,
      );
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directPrepareIdentity'),
        group: SettingsTransferGroup.other,
        order: 0,
        changeParticipant: other,
      );
      final box = SettingsTransferParticipantBox<int>(participant);

      expect(() => box.prepareImport(2), throwsA(isA<StateError>()));
      expect(participant.writeCount, 0);
    });

    test('direct participant 的 reprepare 会校验 change valueType', () {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directReprepareType'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final box = SettingsTransferParticipantBox<int>(participant);
      final wrongTypeChange = SettingsTransferChange<Object?>(
        participant: participant,
        incoming: 2,
        writeValue: 2,
        fingerprint: '2',
        summary: participant.summarizeExport(2),
      );

      expect(
        () => box.reprepareImport(wrongTypeChange),
        throwsA(isA<StateError>()),
      );
    });

    test('direct participant 的 apply 会先拒绝错误 identity', () async {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directApplyIdentity'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final other = _DirectIntParticipant(
        key: const SettingsTransferKey('otherApplyParticipant'),
        group: SettingsTransferGroup.other,
        order: 1,
      );
      final box = SettingsTransferParticipantBox<int>(participant);
      final change = SettingsTransferChange<int>(
        participant: other,
        incoming: 2,
        writeValue: 2,
        fingerprint: '2',
        summary: participant.summarizeExport(2),
      );

      await expectLater(box.applyImport(change), throwsA(isA<StateError>()));
      expect(participant.writeCount, 0);
    });

    test('direct participant 的 apply 会先拒绝错误 change valueType', () async {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directApplyType'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final box = SettingsTransferParticipantBox<int>(participant);
      final wrongTypeChange = SettingsTransferChange<Object?>(
        participant: participant,
        incoming: 2,
        writeValue: 2,
        fingerprint: '2',
        summary: participant.summarizeExport(2),
      );

      await expectLater(
        box.applyImport(wrongTypeChange),
        throwsA(isA<StateError>()),
      );
      expect(participant.writeCount, 0);
    });

    test('direct participant 的 apply 会在写入前拒绝错误值', () async {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directApplyValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final box = SettingsTransferParticipantBox<int>(participant);
      final wrongValueChange = SettingsTransferChange<Object?>(
        participant: participant,
        incoming: 2,
        writeValue: '不是整数',
        fingerprint: 'invalid',
        summary: participant.summarizeExport(2),
      );

      await expectLater(
        box.applyImport(wrongValueChange),
        throwsA(isA<StateError>()),
      );
      expect(participant.writeCount, 0);
    });

    test('direct participant 的 apply 会在正确 change 类型下拒绝错误写入值', () async {
      final participant = _DirectIntParticipant(
        key: const SettingsTransferKey('directApplyTypedValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final box = SettingsTransferParticipantBox<int>(participant);
      final wrongValueChange = SettingsTransferChange<Object?>.erased(
        participant: participant,
        incoming: 2,
        writeValue: '不是整数',
        fingerprint: 'invalid',
        summary: participant.summarizeExport(2),
        valueType: int,
      );

      expect(wrongValueChange.valueType, int);
      await expectLater(
        box.applyImport(wrongValueChange),
        throwsA(isA<StateError>()),
      );
      expect(participant.writeCount, 0);
    });
  });

  test('summary action 与 count 不一致时拒绝构造', () {
    expect(
      () => SettingsTransferSummaryItem(
        key: const SettingsTransferKey('invalidSummary'),
        label: '无效',
        action: SettingsTransferSummaryAction.add,
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => SettingsTransferSummaryItem(
        key: const SettingsTransferKey('invalidSummary'),
        label: '无效',
        action: SettingsTransferSummaryAction.clear,
        count: 1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}

ErasedSettingsTransferParticipant _box<T>(
  SettingsTransferParticipant<T> participant,
) => SettingsTransferParticipantBox.erase(participant);

final class _FakeIntParticipant extends ReplacingValueParticipant<int> {
  _FakeIntParticipant({
    required super.key,
    required super.group,
    required super.order,
    super.label = '整数设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
  });

  int value = 1;
  int readCount = 0;
  int writeCount = 0;

  @override
  int readLocal() {
    readCount += 1;
    return value;
  }

  @override
  bool isEquivalent(int existing, int incoming) => existing == incoming;

  @override
  Object encode(int value) => value;

  @override
  int decode(Object? payload) => payload as int;

  @override
  Future<void> applyImport(int value) async {
    writeCount += 1;
    this.value = value;
  }
}

final class _DirectIntParticipant implements SettingsTransferParticipant<int> {
  _DirectIntParticipant({
    required this.key,
    required this.group,
    required this.order,
    this.changeParticipant,
  }) : label = '直接整数设置',
       sensitivity = SettingsTransferSensitivity.standard;

  @override
  final SettingsTransferKey key;

  @override
  final SettingsTransferGroup group;

  @override
  final int order;

  @override
  final String label;

  @override
  final SettingsTransferSensitivity sensitivity;

  final SettingsTransferParticipant<int>? changeParticipant;
  int readCount = 0;
  int writeCount = 0;

  @override
  int readLocal() {
    readCount += 1;
    return 1;
  }

  @override
  bool shouldExport(int value) => true;

  @override
  Object encode(int value) => value;

  @override
  int decode(Object? payload) => payload as int;

  @override
  SettingsTransferChange<int>? prepareImport({
    required int local,
    required int incoming,
  }) {
    if (local == incoming) return null;
    return SettingsTransferChange<int>(
      participant: changeParticipant ?? this,
      incoming: incoming,
      writeValue: incoming,
      fingerprint: '$incoming',
      summary: summarizeExport(incoming),
    );
  }

  @override
  SettingsTransferSummaryItem summarizeExport(int value) {
    return SettingsTransferSummaryItem(
      key: key,
      label: label,
      action: SettingsTransferSummaryAction.replace,
    );
  }

  @override
  Future<void> applyImport(int value) async {
    writeCount += 1;
  }
}

final class _FakeNullableStringParticipant
    extends ReplacingValueParticipant<String?> {
  _FakeNullableStringParticipant({
    required super.key,
    required super.group,
    required super.order,
    super.label = '可清空设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
  });

  String? value = '已有值';

  @override
  String? readLocal() => value;

  @override
  bool isEquivalent(String? existing, String? incoming) => existing == incoming;

  @override
  bool isEmpty(String? value) => value == null;

  @override
  Object encode(String? value) => {'value': value};

  @override
  String? decode(Object? payload) => (payload as Map)['value'] as String?;

  @override
  Future<void> applyImport(String? value) async {
    this.value = value;
  }
}

final class _FakeCollectionParticipant
    extends MergingCollectionParticipant<int> {
  _FakeCollectionParticipant({
    required super.key,
    required super.group,
    required super.order,
    super.label = '集合设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
  });

  List<int> value = [];

  @override
  List<int> readLocal() => value;

  @override
  bool isEquivalent(int existing, int incoming) => existing == incoming;

  @override
  Object encode(List<int> value) => value;

  @override
  List<int> decode(Object? payload) => [...(payload as List).cast<int>()];

  @override
  Future<void> applyImport(List<int> value) async {
    this.value = [...value];
  }
}
