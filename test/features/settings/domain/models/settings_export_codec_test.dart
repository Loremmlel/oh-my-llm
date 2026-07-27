import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_codec.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';

void main() {
  test('v5 version 字段无损迁移为 v6', () {
    final result = SettingsExportCodec.decodeJson(
      jsonEncode({
        'identifier': SettingsExportData.identifier,
        'version': 5,
        'modelProviders': [],
        'memoryPrompts': [],
        'presetPrompts': [],
        'templatePrompts': [],
        'fixedPromptSequences': [],
      }),
    );

    expect(result, isA<SettingsExportDecodeSuccess>());
    final success = result as SettingsExportDecodeSuccess;
    expect(success.migrated, isTrue);
    expect(success.data.hasContent, isFalse);
  });

  test('旧版、未来版本和 malformed 明确区分', () {
    for (final version in [4, 7]) {
      final result = SettingsExportCodec.decodeJson(
        jsonEncode({
          'identifier': SettingsExportData.identifier,
          'formatVersion': version,
        }),
      );
      expect(result, isA<SettingsExportUnsupportedVersion>());
    }
    expect(SettingsExportCodec.decodeJson('{'), isA<SettingsExportMalformed>());
  });
}
