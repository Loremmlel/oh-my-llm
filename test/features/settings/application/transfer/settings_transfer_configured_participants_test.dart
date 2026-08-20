import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/transfer/participants/preference_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';

void main() {
  test('配置式 replacement builder 保留空 Header 的 clear 语义', () {
    final participant = customHeadersTransferParticipant(
      readLocal: () => const CustomHeadersConfig(
        headers: [CustomHeaderEntry(key: 'X-Test', value: 'secret')],
      ),
      write: (_) async {},
    );

    final change = participant.prepareImport(
      local: participant.readLocal(),
      incoming: const CustomHeadersConfig(),
    );

    expect(change, isNotNull);
    expect(change!.summary.action, SettingsTransferSummaryAction.clear);
    expect(change.summary.trailingText, '清空');
  });
}
