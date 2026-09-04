import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_section.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document_codec.dart';

void main() {
  group('SettingsTransferCoordinator 导出', () {
    test('按分组、section 顺序和 key 确定性导出', () {
      final later = _FakeIntSetting(
        key: 'providerLater',
        group: SettingsTransferGroup.providers,
        order: 1,
        value: 11,
      );
      final earlier = _FakeIntSetting(
        key: 'providerEarlier',
        group: SettingsTransferGroup.providers,
        order: 0,
        value: 12,
      );
      final prompt = _FakeCollectionSetting(
        key: 'promptValues',
        group: SettingsTransferGroup.prompts,
        order: 0,
        value: [1, 2],
      );
      final coordinator = _coordinator([
        prompt.section,
        later.section,
        earlier.section,
      ]);

      final batch = coordinator.exportGroups({
        SettingsTransferGroup.providers,
        SettingsTransferGroup.prompts,
      }) as SettingsExportBatch;

      expect(batch.document.sections.keys, [
        'providerEarlier',
        'providerLater',
        'promptValues',
      ]);
      expect(batch.summaryItems.map((item) => item.key), [
        'providerEarlier',
        'providerLater',
        'promptValues',
      ]);
      expect(earlier.readCount, 1);
    });

    test('空合并集合省略而空替换值保留为清空 section', () {
      final merge = _FakeCollectionSetting(
        key: 'emptyMerge',
        group: SettingsTransferGroup.prompts,
        order: 0,
      );
      String? replacement;
      final replace = SettingsTransferSection.replacing<String?>(
        key: 'emptyReplace',
        group: SettingsTransferGroup.network,
        label: '可清空设置',
        order: 0,
        sensitivity: SettingsTransferSensitivity.standard,
        readLocal: () => replacement,
        write: (value) async => replacement = value,
        encode: (value) => <String, Object?>{'value': value},
        decode: (value) => value['value'] as String?,
        isEmpty: (value) => value == null,
      );
      final coordinator = _coordinator([merge.section, replace]);

      expect(
        coordinator.exportGroups({SettingsTransferGroup.prompts}),
        isA<SettingsExportNoContent>(),
      );
      final batch = coordinator.exportGroups({
        SettingsTransferGroup.network,
      }) as SettingsExportBatch;
      expect(batch.document.sections, {
        'emptyReplace': <String, Object?>{'value': null},
      });
      expect(
        batch.summaryItems.single.action,
        SettingsTransferSummaryAction.clear,
      );
    });

    test('敏感导出未经确认不暴露 JSON', () {
      final setting = _FakeIntSetting(
        key: 'credentialValue',
        group: SettingsTransferGroup.providers,
        order: 0,
        sensitivity: SettingsTransferSensitivity.credentialBearing,
        value: 42,
      );
      final batch = _coordinator([
        setting.section,
      ]).exportGroups({SettingsTransferGroup.providers}) as SettingsExportBatch;

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
    test('路由所有已知 section 并在准备阶段保持零写入', () {
      final provider = _FakeIntSetting(
        key: 'providerValue',
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final other = _FakeIntSetting(
        key: 'otherValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([other.section, provider.section]);

      final ready = coordinator.prepareJson(
        _documentJson({'otherValue': 2, 'providerValue': 3}),
      ) as SettingsImportReady;

      expect(ready.batch.summaryItems.map((item) => item.key), [
        'providerValue',
        'otherValue',
      ]);
      expect(provider.value, 1);
      expect(other.value, 1);
      expect(provider.writeCount, 0);
      expect(other.writeCount, 0);
    });

    test('未知 section 或一个非法 payload 会在写入前拒绝整个文档', () {
      final setting = _FakeIntSetting(
        key: 'knownValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([setting.section]);

      expect(
        coordinator.prepareDocument(_document({'unknownValue': 1})),
        isA<SettingsImportUnknownSection>(),
      );
      expect(setting.decodeCount, 0);
      expect(
        coordinator.prepareDocument(_document({'knownValue': '不是整数'})),
        isA<SettingsImportInvalidSectionPayload>(),
      );
      expect(setting.writeCount, 0);
    });

    test('allowedGroups 在 decode 前拒绝已知但未请求的 section', () {
      final setting = _FakeIntSetting(
        key: 'providerValue',
        group: SettingsTransferGroup.providers,
        order: 0,
      );
      final result = _coordinator([setting.section]).prepareDocument(
        _document({'providerValue': '应在 decode 前拒绝'}),
        allowedGroups: {SettingsTransferGroup.other},
      );

      expect(result, isA<SettingsImportSectionOutsideAllowedGroups>());
      expect(setting.decodeCount, 0);
      expect(setting.writeCount, 0);
    });

    test('区分 malformed、unsupported version 和无变化结果', () {
      final setting = _FakeIntSetting(
        key: 'knownValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final coordinator = _coordinator([setting.section]);

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
      expect(setting.writeCount, 0);
    });
  });

  group('SettingsImportBatch 执行', () {
    test('敏感批次缺少确认时不消费，之后确认可执行', () async {
      final setting = _FakeIntSetting(
        key: 'credentialValue',
        group: SettingsTransferGroup.providers,
        order: 0,
        sensitivity: SettingsTransferSensitivity.credentialBearing,
      );
      final ready = _coordinator([setting.section]).prepareDocument(
        _document({'credentialValue': 2}),
      ) as SettingsImportReady;

      expect(
        await ready.batch.execute(confirmedSensitive: false),
        isA<SettingsImportSensitiveConfirmationRequired>(),
      );
      expect(setting.writeCount, 0);
      expect(
        await ready.batch.execute(confirmedSensitive: true),
        isA<SettingsImportSuccess>(),
      );
      expect(setting.value, 2);
    });

    test('本地变化导致合并摘要变化时返回 stale 且零写入', () async {
      final setting = _FakeCollectionSetting(
        key: 'mergeValues',
        group: SettingsTransferGroup.prompts,
        order: 0,
      );
      final ready = _coordinator([setting.section]).prepareDocument(
        _document({
          'mergeValues': [1, 2],
        }),
      ) as SettingsImportReady;
      setting.value = [1];

      final stale = await ready.batch.execute(
        confirmedSensitive: true,
      ) as SettingsImportStalePreview;

      expect(setting.writeCount, 0);
      expect(stale.refreshedBatch.summaryItems.single.count, 1);
    });

    test('本地替换值变化但最终 fingerprint 相同时继续执行', () async {
      final setting = _FakeIntSetting(
        key: 'replaceValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final ready = _coordinator([
        setting.section,
      ]).prepareDocument(_document({'replaceValue': 3})) as SettingsImportReady;
      setting.value = 2;

      expect(
        await ready.batch.execute(confirmedSensitive: true),
        isA<SettingsImportSuccess>(),
      );
      expect(setting.value, 3);
      expect(setting.writeCount, 1);
    });

    test('两个独立批次同时执行时 writer 临界区不重叠', () async {
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      final secondEntered = Completer<void>();
      var activeWriters = 0;
      var maximumActiveWriters = 0;
      var writeCall = 0;
      final setting = _FakeIntSetting(
        key: 'serializedValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      setting.writeAction = (value) async {
        writeCall += 1;
        activeWriters += 1;
        maximumActiveWriters = activeWriters > maximumActiveWriters
            ? activeWriters
            : maximumActiveWriters;
        if (writeCall == 1) {
          firstEntered.complete();
          await releaseFirst.future;
        } else {
          secondEntered.complete();
        }
        setting.value = value;
        activeWriters -= 1;
      };
      final coordinator = _coordinator([setting.section]);
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
      expect(setting.value, 3);
    });

    test('第一项失败返回 failure 且不执行后续项', () async {
      final failed = _FakeIntSetting(
        key: 'failedValue',
        group: SettingsTransferGroup.other,
        order: 0,
        writeAction: (_) async => throw StateError('secret-write-detail'),
      );
      final notAttempted = _FakeIntSetting(
        key: 'notAttemptedValue',
        group: SettingsTransferGroup.other,
        order: 1,
      );
      final ready =
          _coordinator([notAttempted.section, failed.section]).prepareDocument(
            _document({'notAttemptedValue': 2, 'failedValue': 2}),
          ) as SettingsImportReady;

      final failure = await ready.batch.execute(
        confirmedSensitive: true,
      ) as SettingsImportFailure;

      expect(failure.failedLabel, failed.label);
      expect(failure.safeReason, '写入未完成，请检查本地存储后重试');
      expect(failure.safeReason, isNot(contains('secret-write-detail')));
      expect(failed.writeCount, 1);
      expect(notAttempted.writeCount, 0);
    });

    test('中途失败返回部分成功、失败项和未执行项摘要', () async {
      final completed = _FakeIntSetting(
        key: 'completedValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final failed = _FakeIntSetting(
        key: 'failedValue',
        group: SettingsTransferGroup.other,
        order: 1,
        writeAction: (_) async => throw StateError('secret-write-detail'),
      );
      final notAttempted = _FakeIntSetting(
        key: 'notAttemptedValue',
        group: SettingsTransferGroup.other,
        order: 2,
      );
      final ready =
          _coordinator([
                notAttempted.section,
                failed.section,
                completed.section,
              ]).prepareDocument(
                _document({
                  'notAttemptedValue': 2,
                  'failedValue': 2,
                  'completedValue': 2,
                }),
              )
              as SettingsImportReady;

      final partial = await ready.batch.execute(
        confirmedSensitive: true,
      ) as SettingsImportPartialFailure;

      expect(partial.completed.map((item) => item.key), ['completedValue']);
      expect(partial.failedLabel, failed.label);
      expect(partial.notAttempted.map((item) => item.key), [
        'notAttemptedValue',
      ]);
      expect(notAttempted.writeCount, 0);
    });

    test('成功执行后再次执行返回 already consumed', () async {
      final setting = _FakeIntSetting(
        key: 'oneShotValue',
        group: SettingsTransferGroup.other,
        order: 0,
      );
      final ready = _coordinator([
        setting.section,
      ]).prepareDocument(_document({'oneShotValue': 2})) as SettingsImportReady;

      expect(
        await ready.batch.execute(confirmedSensitive: true),
        isA<SettingsImportSuccess>(),
      );
      expect(
        await ready.batch.execute(confirmedSensitive: true),
        isA<SettingsImportAlreadyConsumed>(),
      );
      expect(setting.writeCount, 1);
    });
  });
}

SettingsTransferCoordinator _coordinator(
  Iterable<SettingsTransferSection> sections,
) => SettingsTransferCoordinator(sections: sections);

String _documentJson(Map<String, Object?> sections) =>
    SettingsTransferDocumentCodec.encodeJson(_document(sections));

SettingsTransferDocument _document(Map<String, Object?> sections) =>
    SettingsTransferDocument(sections: sections);

final class _FakeIntSetting {
  _FakeIntSetting({
    required String key,
    required SettingsTransferGroup group,
    required int order,
    this.value = 1,
    SettingsTransferSensitivity sensitivity =
        SettingsTransferSensitivity.standard,
    this.writeAction,
  }) {
    section = SettingsTransferSection.custom<int>(
      key: key,
      group: group,
      label: label,
      order: order,
      sensitivity: sensitivity,
      readLocal: () {
        readCount += 1;
        return value;
      },
      write: (next) async {
        writeCount += 1;
        final action = writeAction;
        if (action != null) {
          await action(next);
        } else {
          value = next;
        }
      },
      shouldExport: (_) => true,
      encode: (next) => next,
      decode: (payload) {
        decodeCount += 1;
        if (payload is! int) throw const FormatException('必须是整数');
        return payload;
      },
      prepareImport: (local, incoming) {
        if (local == incoming) return null;
        return SettingsTransferChange<int>(
          incoming: incoming,
          writeValue: incoming,
          fingerprint: jsonEncode(incoming),
          summary: SettingsTransferSummaryItem(
            key: key,
            label: label,
            action: SettingsTransferSummaryAction.replace,
          ),
        );
      },
      summarizeExport: (_) => SettingsTransferSummaryItem(
        key: key,
        label: label,
        action: SettingsTransferSummaryAction.replace,
      ),
    );
  }

  late final SettingsTransferSection section;
  int value;
  final String label = '整数设置';
  int readCount = 0;
  int decodeCount = 0;
  int writeCount = 0;
  Future<void> Function(int value)? writeAction;
}

final class _FakeCollectionSetting {
  _FakeCollectionSetting({
    required String key,
    required SettingsTransferGroup group,
    required int order,
    List<int>? value,
  }) : value = value ?? [] {
    section = SettingsTransferSection.custom<List<int>>(
      key: key,
      group: group,
      label: '集合设置',
      order: order,
      sensitivity: SettingsTransferSensitivity.standard,
      readLocal: () => this.value,
      write: (next) async {
        writeCount += 1;
        this.value = List<int>.from(next);
      },
      shouldExport: (next) => next.isNotEmpty,
      encode: (next) => List<int>.unmodifiable(next),
      decode: (payload) {
        if (payload is! List || payload.any((item) => item is! int)) {
          throw const FormatException('必须是整数列表');
        }
        return List<int>.unmodifiable(payload.cast<int>());
      },
      prepareImport: (local, incoming) {
        final additions = incoming
            .where((item) => !local.contains(item))
            .toSet()
            .toList(growable: false);
        if (additions.isEmpty) return null;
        return SettingsTransferChange<List<int>>(
          incoming: incoming,
          writeValue: additions,
          fingerprint: jsonEncode(additions),
          summary: SettingsTransferSummaryItem(
            key: key,
            label: '集合设置',
            action: SettingsTransferSummaryAction.add,
            count: additions.length,
          ),
        );
      },
      summarizeExport: (next) => SettingsTransferSummaryItem(
        key: key,
        label: '集合设置',
        action: SettingsTransferSummaryAction.add,
        count: next.length,
      ),
    );
  }

  late final SettingsTransferSection section;
  List<int> value;
  int writeCount = 0;
}
