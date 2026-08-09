import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_codec.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';

// ── 快照工厂 ────────────────────────────────────────────────────────────────

Map<String, Object?> _providerJson({String? apiProtocol}) {
  return {
    'id': 'provider-1',
    'name': 'OpenAI',
    'apiUrl': 'https://api.openai.com/v1',
    'apiKey': 'sk-test',
    'apiProtocol': ?apiProtocol,
    'models': <Object?>[],
  };
}

Map<String, Object?> _snapshot({
  required int version,
  String versionKey = 'formatVersion',
  required List<Map<String, Object?>> providers,
}) {
  return {
    'identifier': SettingsExportData.identifier,
    versionKey: version,
    'modelProviders': providers,
    'memoryPrompts': <Object?>[],
    'presetPrompts': <Object?>[],
    'templatePrompts': <Object?>[],
    'fixedPromptSequences': <Object?>[],
  };
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  SettingsExportDecodeSuccess decodeSuccess(String json) {
    final result = SettingsExportCodec.decodeJson(json);
    expect(result, isA<SettingsExportDecodeSuccess>());
    return result as SettingsExportDecodeSuccess;
  }

  test('v6 快照导入：全部服务商补 chatCompletions，缺字段才补', () {
    final success = decodeSuccess(
      jsonEncode(
        _snapshot(
          version: 6,
          providers: [
            _providerJson(), // 缺协议字段 → 补 chatCompletions
            _providerJson(apiProtocol: 'responses'), // 已有协议 → 保留
          ],
        ),
      ),
    );

    expect(success.migrated, isTrue);
    expect(success.sourceVersion, 6);
    final providers = success.data.modelProviders;
    expect(providers.length, 2);
    expect(providers[0].apiProtocol, LlmApiProtocol.chatCompletions);
    expect(providers[1].apiProtocol, LlmApiProtocol.responses);
  });

  test('v5 快照经链式迁移同样补全 chatCompletions', () {
    final success = decodeSuccess(
      jsonEncode(
        _snapshot(
          version: 5,
          versionKey: 'version',
          providers: [_providerJson()],
        ),
      ),
    );

    expect(success.migrated, isTrue);
    expect(success.sourceVersion, 5);
    expect(success.data.hasContent, isTrue);
    expect(
      success.data.modelProviders.single.apiProtocol,
      LlmApiProtocol.chatCompletions,
    );
    // 迁移链终点格式为当前版本
    expect(
      jsonDecode(success.data.toJsonString())['formatVersion'],
      SettingsExportData.formatVersion,
    );
  });

  test('v7 快照 round-trip 不迁移，显式协议原样保留', () {
    final success = decodeSuccess(
      jsonEncode(
        _snapshot(
          version: SettingsExportData.formatVersion,
          providers: [_providerJson(apiProtocol: 'anthropic')],
        ),
      ),
    );

    expect(success.migrated, isFalse);
    expect(success.sourceVersion, SettingsExportData.formatVersion);
    expect(
      success.data.modelProviders.single.apiProtocol,
      LlmApiProtocol.anthropic,
    );
  });

  test('旧版、未来版本和 malformed 明确区分', () {
    for (final version in [4, 8]) {
      final result = SettingsExportCodec.decodeJson(
        jsonEncode(_snapshot(version: version, providers: [])),
      );
      expect(result, isA<SettingsExportUnsupportedVersion>());
      expect((result as SettingsExportUnsupportedVersion).version, version);
    }
    expect(SettingsExportCodec.decodeJson('{'), isA<SettingsExportMalformed>());
  });

  test('v7 服务商缺失、null 或未知协议均视为 malformed', () {
    final providers = [
      _providerJson(),
      {..._providerJson(apiProtocol: 'responses'), 'apiProtocol': null},
      _providerJson(apiProtocol: 'future-protocol'),
    ];

    for (final provider in providers) {
      final result = SettingsExportCodec.decodeJson(
        jsonEncode(
          _snapshot(
            version: SettingsExportData.formatVersion,
            providers: [provider],
          ),
        ),
      );
      expect(result, isA<SettingsExportMalformed>());
    }
  });
}
