import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

void main() {
  test('新增 participant 自动贯通导出、摘要和执行', () async {
    var localValue = 'local';
    var writeCount = 0;
    final participant = _StringParticipant(
      readLocal: () => localValue,
      write: (value) async {
        writeCount++;
        localValue = value;
      },
    );
    final catalog = SettingsTransferCatalog([
      SettingsTransferParticipantBox.erase(participant),
    ]);
    final facade = RiverpodSettingsSyncFacade(
      catalog: catalog,
      coordinator: SettingsTransferCoordinator(catalog: catalog),
    );

    final exported = facade.exportGroups({
      const SettingsSyncGroupId('providers'),
    });
    expect(exported.sections, {'extraSetting': 'local'});

    final prepared = facade.prepareIncoming(
      SettingsTransferDocument(sections: {'extraSetting': 'incoming'}),
      requestedGroups: {const SettingsSyncGroupId('providers')},
    );
    expect(prepared.summaries, [
      const SettingsSyncSummaryItem(label: '额外设置', trailingText: '替换'),
    ]);
    expect(prepared.containsSensitive, isFalse);

    final result = await prepared.execute(confirmedSensitive: false);
    expect(result, isA<SettingsSyncImportSuccess>());
    expect(localValue, 'incoming');
    expect(writeCount, 1);
  });
}

final class _StringParticipant extends ReplacingValueParticipant<String> {
  _StringParticipant({required this._readLocal, required this._write})
    : super(
        key: const SettingsTransferKey('extraSetting'),
        group: SettingsTransferGroup.providers,
        label: '额外设置',
        order: 99,
        sensitivity: SettingsTransferSensitivity.standard,
      );

  final String Function() _readLocal;
  final Future<void> Function(String value) _write;

  @override
  String readLocal() => _readLocal();

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? payload) {
    if (payload is! String) throw const FormatException();
    return payload;
  }

  @override
  bool isEquivalent(String existing, String incoming) => existing == incoming;

  @override
  Future<void> applyImport(String value) => _write(value);
}
