import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_section.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/domain/models/session/sync_pairing.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

void main() {
  test('v4 配对记录不再携带分类授权', () {
    final record = SyncPairingRecord(
      peer: const SyncPeerIdentity(id: 'peer', displayName: 'Peer'),
      createdAt: DateTime(2026),
      lastUsedAt: DateTime(2026),
    );
    expect(record.toJson(), isNot(contains('grantedCategories')));
  });

  test('v9 facade 重试时已完成 section 变为 no-op 且只执行剩余变更', () async {
    final completed = _RetryingIntSection(
      key: 'completedValue',
      order: 0,
      value: 1,
    );
    final failed = _RetryingIntSection(
      key: 'failedValue',
      order: 1,
      value: 1,
      failFirstWrite: true,
    );
    final coordinator = SettingsTransferCoordinator(
      sections: [completed.section, failed.section],
    );
    final facade = RiverpodSettingsSyncFacade(coordinator: coordinator);
    final groups = {const SettingsSyncGroupId('other')};
    final document = SettingsTransferDocument(
      sections: {'completedValue': 2, 'failedValue': 2},
    );

    final first = facade.prepareIncoming(document, requestedGroups: groups);
    final firstResult = await first.execute(confirmedSensitive: false);
    final partial = firstResult as SettingsSyncImportPartialFailure;
    expect(partial.completed.map((item) => item.label), ['整数设置']);
    expect(partial.failedLabel, '整数设置');
    expect(partial.notAttempted, isEmpty);
    expect(completed.writeCount, 1);
    expect(failed.writeCount, 1);
    expect(completed.value, 2);
    expect(failed.value, 1);

    final retry = facade.prepareIncoming(document, requestedGroups: groups);
    expect(retry.summaries.map((item) => item.label), ['整数设置']);
    final retryResult = await retry.execute(confirmedSensitive: false);

    expect(retryResult, isA<SettingsSyncImportSuccess>());
    expect(completed.writeCount, 1);
    expect(failed.writeCount, 2);
    expect(failed.value, 2);
  });
}

final class _RetryingIntSection {
  _RetryingIntSection({
    required String key,
    required int order,
    required this.value,
    this.failFirstWrite = false,
  }) {
    section = SettingsTransferSection.custom<int>(
      key: key,
      group: SettingsTransferGroup.other,
      label: '整数设置',
      order: order,
      sensitivity: SettingsTransferSensitivity.standard,
      readLocal: () => value,
      write: (next) async {
        writeCount += 1;
        if (failFirstWrite) {
          failFirstWrite = false;
          throw StateError('故意注入的 section 写入失败');
        }
        value = next;
      },
      shouldExport: (_) => true,
      encode: (next) => next,
      decode: (payload) {
        if (payload is! int) throw const FormatException('必须是整数');
        return payload;
      },
      prepareImport: (local, incoming) {
        if (local == incoming) return null;
        return SettingsTransferChange<int>(
          incoming: incoming,
          writeValue: incoming,
          fingerprint: '$incoming',
          summary: SettingsTransferSummaryItem(
            key: key,
            label: '整数设置',
            action: SettingsTransferSummaryAction.replace,
          ),
        );
      },
      summarizeExport: (_) => SettingsTransferSummaryItem(
        key: key,
        label: '整数设置',
        action: SettingsTransferSummaryAction.replace,
      ),
    );
  }

  late final SettingsTransferSection section;
  int value;
  bool failFirstWrite;
  int writeCount = 0;
}
