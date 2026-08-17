import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_codec.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';

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

Map<String, Object?> _variableJson({
  required String name,
  String defaultValue = '',
  String type = 'text',
  List<String> options = const [],
}) {
  return {
    'name': name,
    'defaultValue': defaultValue,
    'type': type,
    'options': options,
  };
}

Map<String, Object?> _templateJson({
  String id = 'tpl-1',
  String title = '条件模板',
  required String content,
  List<Map<String, Object?>> variables = const [],
}) {
  return {
    'id': id,
    'title': title,
    'content': content,
    'variables': variables,
    'updatedAt': '2026-01-01T00:00:00.000',
  };
}

/// 构造只含一条模板的 v8 快照（服务商显式协议；导入端会逐条编译校验模板
/// 定义，因此快照中的模板内容与存储变量必须满足 v8 编译校验）。
Map<String, Object?> _snapshotWithTemplate(Map<String, Object?> template) {
  return _snapshot(
    version: 8,
    providers: [_providerJson(apiProtocol: 'chatCompletions')],
  )..['templatePrompts'] = [template];
}

/// 一个可在 v8 round-trip 中整体还原的单选模板夹具。
///
/// 源声明与存储变量一致：正文声明顺序为「人称(select)、正文」，
/// 存储变量按同一顺序提供，默认值取第二个选项「二」。
TemplatePrompt _selectTemplate() {
  return TemplatePrompt(
    id: 'tpl-select',
    title: '条件模板',
    content:
        '{{人称:select|一|二|三}}{{#if 人称 == "一"}}第一人称{{else}}其他{{/if}}，正文：{{正文}}',
    variables: const [
      TemplatePromptVariable(
        name: '人称',
        type: TemplatePromptVariableType.select,
        defaultValue: '二',
        options: ['一', '二', '三'],
      ),
      TemplatePromptVariable(name: templatePromptBodyVariableName),
    ],
    updatedAt: DateTime(2026, 1, 1),
  );
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

  test('v7 快照迁移到 v8，显式协议原样保留', () {
    final success = decodeSuccess(
      jsonEncode(
        _snapshot(
          version: 7,
          providers: [_providerJson(apiProtocol: 'anthropic')],
        ),
      ),
    );

    expect(success.migrated, isTrue);
    expect(success.sourceVersion, 7);
    expect(
      success.data.modelProviders.single.apiProtocol,
      LlmApiProtocol.anthropic,
    );
    expect(
      jsonDecode(success.data.toJsonString())['formatVersion'],
      SettingsExportData.formatVersion,
    );
  });

  test('v6→v7 迁移写入字面量 7，再由 v7→v8 接力', () {
    final v7 = const SettingsExportFormatMigratorV6ToV7().migrate({
      'formatVersion': 6,
      'modelProviders': [_providerJson()],
    });
    // 中间格式必须写字面量 7，不能跳级到当前版本号。
    expect(v7['formatVersion'], 7);
    final v8 = const SettingsExportFormatMigratorV7ToV8().migrate(v7);
    expect(v8['formatVersion'], 8);
  });

  test('v8 当前快照 round-trip 不迁移，显式协议原样保留', () {
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

  test('v8 单选模板 round-trip 保留有序选项与字符串默认值', () {
    final template = _selectTemplate();
    final data = SettingsExportData(
      modelProviders: const [],
      memoryPrompts: const [],
      presetPrompts: const [],
      templatePrompts: [template],
      fixedPromptSequences: const [],
    );

    final success = decodeSuccess(data.toJsonString());
    expect(success.sourceVersion, 8);
    expect(success.migrated, isFalse);
    final decoded = success.data.templatePrompts.single;
    expect(decoded, template);
    final select = decoded.variables.singleWhere(
      (variable) => variable.isSelect,
    );
    expect(select.options, ['一', '二', '三']);
    expect(select.defaultValue, '二');
  });

  test('v5-v7 的 text/number 模板成功迁移到 v8', () {
    final template = _templateJson(
      content: '请处理{{正文}}，重复{{次数:number}}次',
      variables: [
        _variableJson(name: templatePromptBodyVariableName),
        _variableJson(name: '次数', defaultValue: '2', type: 'number'),
      ],
    );
    for (final version in [5, 6, 7]) {
      final success = decodeSuccess(
        jsonEncode(
          _snapshot(
            version: version,
            versionKey: version == 5 ? 'version' : 'formatVersion',
            providers: [
              // v5/v6 由迁移器补协议；v7 必须显式协议才结构有效。
              if (version == 7)
                _providerJson(apiProtocol: 'chatCompletions')
              else
                _providerJson(),
            ],
          )..['templatePrompts'] = [template],
        ),
      );

      expect(success.sourceVersion, version, reason: 'v$version');
      expect(success.migrated, isTrue, reason: 'v$version');
      // 迁移链终点格式为当前版本（循环内自包含，不依赖其他用例兜底）
      expect(
        jsonDecode(success.data.toJsonString())['formatVersion'],
        SettingsExportData.formatVersion,
        reason: 'v$version',
      );
      final migrated = success.data.templatePrompts.single;
      expect(migrated.variables, hasLength(2), reason: 'v$version');
      final number = migrated.variables.singleWhere(
        (variable) => variable.isNumber,
      );
      expect(number.defaultValue, '2', reason: 'v$version');
    }
  });

  test('v8 模板定义按编译器错误族报告 malformed', () {
    // 每个夹具对应一类编译器校验：内容语法、结构约束或存储元数据一致性。
    final cases = <(String, Map<String, Object?>)>[
      (
        '未闭合条件块',
        _templateJson(
          content: '{{x}}{{#if x == "a"}}未闭合',
          variables: [_variableJson(name: 'x')],
        ),
      ),
      (
        '嵌套条件块',
        _templateJson(
          content: '{{#if 人称 == "一"}}\n{{#if 风格 == "短"}}x{{/if}}\n{{/if}}',
          variables: [
            _variableJson(name: '人称'),
            _variableJson(name: '风格'),
          ],
        ),
      ),
      (
        '存储变量与正文声明不一致',
        _templateJson(content: '请用{{语气}}回复', variables: const []),
      ),
      (
        '单选默认值不在选项列表中',
        _templateJson(
          content: '{{人称:select|一|二|三}}',
          variables: [
            _variableJson(
              name: '人称',
              defaultValue: '四',
              type: 'select',
              options: ['一', '二', '三'],
            ),
          ],
        ),
      ),
      (
        '条件分支内出现正文',
        _templateJson(
          content: '{{人称:select|一|二|三}}\n{{#if 人称 == "一"}}\n{{正文}}\n{{/if}}',
          variables: [
            _variableJson(name: '人称', type: 'select', options: ['一', '二', '三']),
            _variableJson(name: templatePromptBodyVariableName),
          ],
        ),
      ),
    ];

    for (final (name, template) in cases) {
      final result = SettingsExportCodec.decodeJson(
        jsonEncode(_snapshotWithTemplate(template)),
      );
      expect(result, isA<SettingsExportMalformed>(), reason: name);
    }
  });

  test('v8 当前快照缺失、null 或未知协议的服务商均视为 malformed', () {
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

  test('旧版、未来版本和 malformed 明确区分', () {
    for (final version in [4, 9]) {
      final result = SettingsExportCodec.decodeJson(
        jsonEncode(_snapshot(version: version, providers: [])),
      );
      expect(result, isA<SettingsExportUnsupportedVersion>());
      expect((result as SettingsExportUnsupportedVersion).version, version);
    }
    expect(SettingsExportCodec.decodeJson('{'), isA<SettingsExportMalformed>());
  });
}
