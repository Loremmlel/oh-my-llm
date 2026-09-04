import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_coordinator.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_section.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_transfer_document.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';

void main() {
  test('Coordinator section 自动贯通导出、摘要和执行', () async {
    var localValue = 'local';
    var writeCount = 0;
    final section = SettingsTransferSection.replacing<String>(
      key: 'extraSetting',
      group: SettingsTransferGroup.providers,
      label: '额外设置',
      order: 99,
      sensitivity: SettingsTransferSensitivity.standard,
      readLocal: () => localValue,
      write: (value) async {
        writeCount++;
        localValue = value;
      },
      encode: (value) => {'value': value},
      decode: (payload) => payload['value']! as String,
    );
    final coordinator = SettingsTransferCoordinator(sections: [section]);
    final facade = RiverpodSettingsSyncFacade(coordinator: coordinator);

    final exported = facade.exportGroups({
      const SettingsSyncGroupId('providers'),
    });
    expect(exported.sections, {
      'extraSetting': {'value': 'local'},
    });

    final prepared = facade.prepareIncoming(
      SettingsTransferDocument(
        sections: {
          'extraSetting': {'value': 'incoming'},
        },
      ),
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
