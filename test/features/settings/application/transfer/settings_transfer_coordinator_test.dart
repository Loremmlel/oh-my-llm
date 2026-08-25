import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';

void main() {
  group('SettingsTransferCoordinator 导出', () {
    test('按注册表顺序覆盖单组、多组和类型化单值导出', () {
      final provider = _FakeIntParticipant(
        key: const SettingsTransferKey('providerValue'),
        group: SettingsTransferGroup.providers,
        order: 0,
        value: 11,
      );
      final prompt = _FakeCollectionParticipant(
        key: const SettingsTransferKey('promptValues'),
        group: SettingsTransferGroup.prompts,
        order: 0,
        value: [1, 2],
      );
      final coordinator = _coordinator([_box(prompt), _box(provider)]);

      final oneGroup = coordinator.exportGroups({
        SettingsTransferGroup.providers,
      });
      final oneGroupBatch = oneGroup as SettingsExportBatch;
      expect(oneGroupBatch.document.sections, {'providerValue': 11});
      expect(oneGroupBatch.summaryItems.map((item) => item.key.value), [
        'providerValue',
      ]);
      expect(provider.readCount, 1);

      final multipleGroups = coordinator.exportGroups({
        SettingsTransferGroup.providers,
        SettingsTransferGroup.prompts,
      });
      final multipleGroupsBatch = multipleGroups as SettingsExportBatch;
      expect(multipleGroupsBatch.document.sections.keys, [
        'providerValue',
        'promptValues',
      ]);

      final singleValue = coordinator.exportValue(prompt, [3]);
      final singleValueBatch = singleValue as SettingsExportBatch;
      expect(singleValueBatch.document.sections, {
        'promptValues': [3],
      });
      expect(singleValueBatch.summaryItems.single.trailingText, '新增 1 项');
    });

    test('空合并集合省略而空替换值保留为清空 section', () {
      final merge = _FakeCollectionParticipant(
        key: const SettingsTransferKey('emptyMerge'),
        group: SettingsTransferGroup.prompts,
        order: 0,
      );
      final replace = _FakeNullableStringParticipant(
        key: const SettingsTransferKey('emptyReplace'),
        group: SettingsTransferGroup.network,
        order: 0,
        value: null,
      );
      final coordinator = _coordinator([_box(merge), _box(replace)]);

      final mergeExport = coordinator.exportGroups({
        SettingsTransferGroup.prompts,
      });
      expect(mergeExport, isA<SettingsExportNoContent>());

      final replaceExport = coordinator.exportGroups({
        SettingsTransferGroup.network,
      });
      final replaceBatch = replaceExport as SettingsExportBatch;
      expect(replaceBatch.document.sections, {
        'emptyReplace': <String, Object?>{'value': null},
      });
      expect(
        replaceBatch.summaryItems.single.action,
        SettingsTransferSummaryAction.clear,
      );
    });

    test('敏感导出未经确认不暴露 JSON', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('credentialValue'),
        group: SettingsTransferGroup.providers,
        order: 0,
        sensitivity: SettingsTransferSensitivity.credentialBearing,
        value: 42,
      );
      final coordinator = _coordinator([_box(participant)]);
      final batch = coordinator.exportGroups({
        SettingsTransferGroup.providers,
      }) as SettingsExportBatch;

      expect(
        batch.exposeJson(confirmedSensitive: false),
        isA<SettingsExportSensitiveConfirmationRequired>(),
      );
      final exposed = batch.exposeJson(confirmedSensitive: true);
      expect(exposed, isA<SettingsExportJsonExposed>());
      expect((exposed as SettingsExportJsonExposed).text, contains('42'));
    });
  });

  group('SettingsTransferCoordinator 准备', () {
    test('JSON 导入不依赖当前分组并路由所有已知 section', () {
      final provider = _FakeIntParticipant(
        key: const SettingsTransferKey('providerValue'),
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final other = _FakeIntParticipant(
        key: const SettingsTransferKey('otherValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(other), _box(provider)]);

      final result = coordinator.prepareJson(
        _documentJson({'otherValue': 2, 'providerValue': 3}),
      );

      final ready = result as SettingsImportReady;
      expect(ready.batch.summaryItems.map((item) => item.key.value), [
        'providerValue',
        'otherValue',
      ]);
      expect(provider.value, 1);
      expect(other.value, 1);
      expect(provider.writeCount, 0);
      expect(other.writeCount, 0);
    });

    test('未知 section 或一个非法 payload 会在写入前拒绝整个文档', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('knownValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);

      final unknown = coordinator.prepareDocument(
        _document({'unknownValue': 1}),
      );
      expect(unknown, isA<SettingsImportUnknownSection>());
      expect(participant.decodeCount, 0);
      expect(participant.writeCount, 0);

      final invalid = coordinator.prepareDocument(
        _document({'knownValue': '不是整数'}),
      );
      expect(invalid, isA<SettingsImportInvalidParticipantPayload>());
      expect(participant.writeCount, 0);
    });

    test('allowedGroups 在 participant decode 前拒绝已知但未请求的 section', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('providerValue'),
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);

      final result = coordinator.prepareDocument(
        _document({'providerValue': '应在 decode 前拒绝'}),
        allowedGroups: {SettingsTransferGroup.other},
      );

      expect(result, isA<SettingsImportSectionOutsideAllowedGroups>());
      expect(participant.decodeCount, 0);
      expect(participant.writeCount, 0);
    });

    test('区分 malformed、unsupported version 和无变化结果', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('knownValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);

      expect(coordinator.prepareJson(null), isA<SettingsImportMalformed>());
      expect(
        coordinator.prepareJson(
          jsonEncode({
            'identifier': SettingsTransferDocument.identifier,
            'formatVersion': SettingsTransferDocument.formatVersion - 1,
            'sections': <String, Object?>{},
          }),
        ),
        isA<SettingsImportUnsupportedVersion>(),
      );
      expect(
        coordinator.prepareDocument(_document({'knownValue': 1})),
        isA<SettingsImportNoChanges>(),
      );
      expect(participant.writeCount, 0);
    });

    test('准备阶段全程零写入且远端值变化时返回可执行批次', () {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('knownValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);

      final result = coordinator.prepareJson(_documentJson({'knownValue': 2}));

      expect(result, isA<SettingsImportReady>());
      expect(participant.writeCount, 0);
      expect(participant.value, 1);
    });
  });

  group('SettingsImportBatch 执行', () {
    test('敏感批次缺少确认时不消费，之后确认可执行', () async {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('credentialValue'),
        group: SettingsTransferGroup.providers,
        order: 0,
        sensitivity: SettingsTransferSensitivity.credentialBearing,
      );
      final coordinator = _coordinator([_box(participant)]);
      final ready = coordinator.prepareDocument(
        _document({'credentialValue': 2}),
      ) as SettingsImportReady;

      final rejected = await ready.batch.execute(confirmedSensitive: false);
      expect(rejected, isA<SettingsImportSensitiveConfirmationRequired>());
      expect(participant.writeCount, 0);

      final success = await ready.batch.execute(confirmedSensitive: true);
      expect(success, isA<SettingsImportSuccess>());
      expect(participant.writeCount, 1);
      expect(participant.value, 2);
    });

    test('本地变化导致合并 fingerprint 和摘要变化时返回 stale 且零写入', () async {
      final participant = _FakeCollectionParticipant(
        key: const SettingsTransferKey('mergeValues'),
        group: SettingsTransferGroup.prompts,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);
      final ready = coordinator.prepareDocument(
        _document({
          'mergeValues': [1, 2],
        }),
      ) as SettingsImportReady;
      participant.value = [1];

      final result = await ready.batch.execute(confirmedSensitive: true);

      final stale = result as SettingsImportStalePreview;
      expect(participant.writeCount, 0);
      expect(stale.refreshedBatch.summaryItems.single.count, 1);
    });

    test('本地替换值变化但最终 fingerprint 相同时继续执行', () async {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('replaceValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);
      final ready = coordinator.prepareDocument(
        _document({'replaceValue': 3}),
      ) as SettingsImportReady;
      participant.value = 2;

      final result = await ready.batch.execute(confirmedSensitive: true);

      expect(result, isA<SettingsImportSuccess>());
      expect(participant.value, 3);
      expect(participant.writeCount, 1);
    });

    test('两个独立批次同时执行时 writer 临界区不重叠', () async {
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      final secondEntered = Completer<void>();
      var activeWriters = 0;
      var maximumActiveWriters = 0;
      var writeCall = 0;
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('serializedValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      participant.writeAction = (value) async {
        writeCall += 1;
        activeWriters += 1;
        if (activeWriters > maximumActiveWriters) {
          maximumActiveWriters = activeWriters;
        }
        if (writeCall == 1) {
          firstEntered.complete();
          await releaseFirst.future;
        } else {
          secondEntered.complete();
        }
        participant.value = value;
        activeWriters -= 1;
      };
      final coordinator = _coordinator([_box(participant)]);
      final first = coordinator.prepareDocument(
        _document({'serializedValue': 2}),
      ) as SettingsImportReady;
      final second = coordinator.prepareDocument(
        _document({'serializedValue': 3}),
      ) as SettingsImportReady;

      final firstExecution = first.batch.execute(confirmedSensitive: true);
      await firstEntered.future;
      final secondExecution = second.batch.execute(confirmedSensitive: true);
      expect(secondEntered.isCompleted, isFalse);

      releaseFirst.complete();
      await firstExecution;
      await secondExecution;

      expect(secondEntered.isCompleted, isTrue);
      expect(maximumActiveWriters, 1);
      expect(participant.value, 3);
    });

    test('第一项失败返回 failure 且不执行后续项', () async {
      final failed = _FakeIntParticipant(
        key: const SettingsTransferKey('failedValue'),
        group: SettingsTransferGroup.other,
        order: 0,
        writeAction: (_) async {
          throw StateError('secret-write-detail');
        },
      );
      final notAttempted = _FakeIntParticipant(
        key: const SettingsTransferKey('notAttemptedValue'),
        group: SettingsTransferGroup.other,
        order: 1,
      );
      final coordinator = _coordinator([_box(notAttempted), _box(failed)]);
      final ready = coordinator.prepareDocument(
        _document({'notAttemptedValue': 2, 'failedValue': 2}),
      ) as SettingsImportReady;

      final result = await ready.batch.execute(confirmedSensitive: true);

      final failure = result as SettingsImportFailure;
      expect(failure.failedLabel, failed.label);
      expect(failure.safeReason, '写入未完成，请检查本地存储后重试');
      expect(failure.safeReason, isNot(contains('secret-write-detail')));
      expect(failed.writeCount, 1);
      expect(notAttempted.writeCount, 0);
    });

    test('中途失败返回部分成功、失败项和未执行项摘要', () async {
      final completed = _FakeIntParticipant(
        key: const SettingsTransferKey('completedValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final failed = _FakeIntParticipant(
        key: const SettingsTransferKey('failedValue'),
        group: SettingsTransferGroup.other,
        order: 1,
        writeAction: (_) async {
          throw StateError('secret-write-detail');
        },
      );
      final notAttempted = _FakeIntParticipant(
        key: const SettingsTransferKey('notAttemptedValue'),
        group: SettingsTransferGroup.other,
        order: 2,
      );
      final coordinator = _coordinator([
        _box(notAttempted),
        _box(failed),
        _box(completed),
      ]);
      final ready = coordinator.prepareDocument(
        _document({
          'notAttemptedValue': 2,
          'failedValue': 2,
          'completedValue': 2,
        }),
      ) as SettingsImportReady;

      final result = await ready.batch.execute(confirmedSensitive: true);

      final partial = result as SettingsImportPartialFailure;
      expect(partial.completed.map((item) => item.key.value), [
        'completedValue',
      ]);
      expect(partial.failedLabel, failed.label);
      expect(partial.notAttempted.map((item) => item.key.value), [
        'notAttemptedValue',
      ]);
      expect(partial.safeReason, '写入未完成，请检查本地存储后重试');
      expect(failed.writeCount, 1);
      expect(notAttempted.writeCount, 0);
    });

    test('成功执行后再次执行返回 already consumed', () async {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('oneShotValue'),
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([_box(participant)]);
      final ready = coordinator.prepareDocument(
        _document({'oneShotValue': 2}),
      ) as SettingsImportReady;

      final first = await ready.batch.execute(confirmedSensitive: true);
      final second = await ready.batch.execute(confirmedSensitive: true);

      expect(first, isA<SettingsImportSuccess>());
      expect(second, isA<SettingsImportAlreadyConsumed>());
      expect(participant.writeCount, 1);
    });

    test('新增 fake participant 无需 coordinator 分支即可完成导出准备和执行', () async {
      final participant = _FakeIntParticipant(
        key: const SettingsTransferKey('newFakeParticipant'),
        group: SettingsTransferGroup.network,
        order: 9,
        value: 1,
      );
      final coordinator = _coordinator([_box(participant)]);

      final exported = coordinator.exportGroups({
        SettingsTransferGroup.network,
      }) as SettingsExportBatch;
      expect(exported.document.sections, {'newFakeParticipant': 1});

      final prepared = coordinator.prepareDocument(
        _document({'newFakeParticipant': 2}),
      ) as SettingsImportReady;
      expect(
        prepared.batch.summaryItems.single.key.value,
        'newFakeParticipant',
      );

      final result = await prepared.batch.execute(confirmedSensitive: true);
      expect(result, isA<SettingsImportSuccess>());
      expect(participant.value, 2);
    });
  });
}

SettingsTransferCoordinator _coordinator(
  Iterable<ErasedSettingsTransferParticipant> participants,
) {
  return SettingsTransferCoordinator(
    catalog: SettingsTransferCatalog(participants),
  );
}

ErasedSettingsTransferParticipant _box<T>(
  SettingsTransferParticipant<T> participant,
) => SettingsTransferParticipantBox.erase(participant);

String _documentJson(Map<String, Object?> sections) =>
    SettingsTransferDocumentCodec.encodeJson(_document(sections));

SettingsTransferDocument _document(Map<String, Object?> sections) =>
    SettingsTransferDocument(sections: sections);

final class _FakeIntParticipant extends ReplacingValueParticipant<int> {
  _FakeIntParticipant({
    required super.key,
    required super.group,
    required super.order,
    this.value = 1,
    super.label = '整数设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
    this.writeAction,
  });

  int value;
  int readCount = 0;
  int decodeCount = 0;
  int writeCount = 0;
  Future<void> Function(int value)? writeAction;

  @override
  bool isEquivalent(int existing, int incoming) => existing == incoming;

  @override
  int readLocal() {
    readCount += 1;
    return value;
  }

  @override
  Object encode(int value) => value;

  @override
  int decode(Object? payload) {
    decodeCount += 1;
    if (payload is! int) throw const FormatException('必须是整数');
    return payload;
  }

  @override
  Future<void> applyImport(int value) async {
    writeCount += 1;
    if (writeAction case final action?) {
      await action(value);
      return;
    }
    this.value = value;
  }
}

final class _FakeNullableStringParticipant
    extends ReplacingValueParticipant<String?> {
  _FakeNullableStringParticipant({
    required super.key,
    required super.group,
    required super.order,
    required this.value,
    super.label = '可清空设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
  });

  String? value;

  @override
  String? readLocal() => value;

  @override
  bool isEquivalent(String? existing, String? incoming) => existing == incoming;

  @override
  bool isEmpty(String? value) => value == null;

  @override
  Object encode(String? value) => <String, Object?>{'value': value};

  @override
  String? decode(Object? payload) {
    if (payload is! Map || !payload.containsKey('value')) {
      throw const FormatException('必须是 nullable object');
    }
    final value = payload['value'];
    if (value != null && value is! String) {
      throw const FormatException('value 必须是字符串或 null');
    }
    return value as String?;
  }

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
    List<int>? value,
    super.label = '集合设置',
    super.sensitivity = SettingsTransferSensitivity.standard,
  }) : value = value ?? [];

  List<int> value;
  int writeCount = 0;

  @override
  List<int> readLocal() => value;

  @override
  bool isEquivalent(int existing, int incoming) => existing == incoming;

  @override
  Object encode(List<int> value) => List<int>.unmodifiable(value);

  @override
  List<int> decode(Object? payload) {
    if (payload is! List || payload.any((item) => item is! int)) {
      throw const FormatException('必须是整数列表');
    }
    return List<int>.unmodifiable(payload.cast<int>());
  }

  @override
  Future<void> applyImport(List<int> value) async {
    writeCount += 1;
    this.value = List<int>.from(value);
  }
}
