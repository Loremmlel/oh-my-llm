import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/model_provider_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/preference_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19);

  group('集合型 Settings transfer participant', () {
    test('五个 participant 暴露稳定 key、分组、顺序和敏感级别', () {
      final participants = _createParticipants();

      expect(
        participants
            .map(
              (participant) => (
                key: participant.key.value,
                group: participant.group,
                order: participant.order,
                sensitivity: participant.sensitivity,
              ),
            )
            .toList(),
        [
          (
            key: 'modelProviders',
            group: SettingsTransferGroup.providers,
            order: 0,
            sensitivity: SettingsTransferSensitivity.credentialBearing,
          ),
          (
            key: 'presetPrompts',
            group: SettingsTransferGroup.presets,
            order: 0,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
          (
            key: 'memoryPrompts',
            group: SettingsTransferGroup.prompts,
            order: 0,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
          (
            key: 'templatePrompts',
            group: SettingsTransferGroup.prompts,
            order: 1,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
          (
            key: 'fixedPromptSequences',
            group: SettingsTransferGroup.prompts,
            order: 2,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
        ],
      );
    });

    test('五个 participant 都能完成模型列表编解码 round-trip', () {
      final provider = _provider();
      final preset = _preset(now);
      final memory = _memory(now);
      final template = _template(now);
      final sequence = _sequence(now);

      _expectRoundTrip(_createProviderParticipant(), [provider]);
      _expectRoundTrip(_createPresetParticipant(), [preset]);
      _expectRoundTrip(_createMemoryParticipant(), [memory]);
      _expectRoundTrip(_createTemplateParticipant(), [template]);
      _expectRoundTrip(_createSequenceParticipant(), [sequence]);
    });

    test('空集合不会导出', () {
      _expectEmptyExport(_createProviderParticipant());
      _expectEmptyExport(_createPresetParticipant());
      _expectEmptyExport(_createMemoryParticipant());
      _expectEmptyExport(_createTemplateParticipant());
      _expectEmptyExport(_createSequenceParticipant());
    });

    test('所有列表解码器都拒绝非 map 元素', () {
      expect(
        () => _createProviderParticipant().decode([1]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _createPresetParticipant().decode([1]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _createMemoryParticipant().decode([1]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _createTemplateParticipant().decode([1]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _createSequenceParticipant().decode([1]),
        throwsA(isA<FormatException>()),
      );
    });

    test('provider 解码器拒绝缺少或为空的 apiProtocol', () {
      final participant = _createProviderParticipant();
      final json = _provider().toJson();

      for (final malformed in [
        {...json}..remove('apiProtocol'),
        {...json, 'apiProtocol': null},
      ]) {
        expect(
          () => participant.decode([malformed]),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('template 解码器在任一模板编译失败时拒绝整个列表', () {
      final participant = _createTemplateParticipant();
      final invalid = _template(
        now,
      ).copyWith(content: '{{#if 人称 == "一"}}\n未闭合内容', variables: const []);

      expect(
        () => participant.decode([invalid.toJson()]),
        throwsA(isA<FormatException>()),
      );
    });

    test('五个 participant 对等价内容生成 no-op', () {
      final provider = _providerParticipantNoOpCase();
      final preset = _presetParticipantNoOpCase(now);
      final memory = _memoryParticipantNoOpCase(now);
      final template = _templateParticipantNoOpCase(now);
      final sequence = _sequenceParticipantNoOpCase(now);

      expect(provider, isNull);
      expect(preset, isNull);
      expect(memory, isNull);
      expect(template, isNull);
      expect(sequence, isNull);
    });

    test('五个 participant 对新增内容生成安全的 add 摘要', () {
      final provider = _createProviderParticipant();
      final preset = _createPresetParticipant();
      final memory = _createMemoryParticipant();
      final template = _createTemplateParticipant();
      final sequence = _createSequenceParticipant();
      _expectAddSummary(provider, [_provider()]);
      _expectAddSummary(preset, [_preset(now)]);
      _expectAddSummary(memory, [_memory(now)]);
      _expectAddSummary(template, [_template(now)]);
      _expectAddSummary(sequence, [_sequence(now)]);
    });

    test('provider participant 写入完整合并后的服务商列表且摘要不含密钥', () {
      final local = _provider(
        id: 'local-provider',
        name: '本地服务商',
        apiUrl: 'https://same.example.com/v1',
        apiKey: 'provider-secret',
        models: [_model(modelName: 'local-model')],
      );
      final incoming = _provider(
        id: 'incoming-provider',
        name: '传入服务商',
        apiUrl: 'https://same.example.com',
        apiKey: 'provider-secret',
        models: [_model(id: 'incoming-model', modelName: 'new-model')],
      );
      final participant = ModelProviderTransferParticipant(
        readLocal: () => [local],
        write: (_) async {},
      );

      final change = participant.prepareImport(
        local: [local],
        incoming: [incoming],
      );

      expect(change, isNotNull);
      expect(change!.writeValue, hasLength(1));
      final merged = change.writeValue.single;
      expect(merged.id, 'local-provider');
      expect(merged.models.map((model) => model.modelName).toSet(), {
        'local-model',
        'new-model',
      });
      expect(change.summary.trailingText, '新增 1 项');
      expect(
        '${change.summary.label} ${change.summary.trailingText}',
        isNot(contains('provider-secret')),
      );
    });
  });

  group('替换型 Settings transfer participant', () {
    test('四个 participant 暴露稳定 key、分组、顺序和敏感级别', () {
      final participants = _createPreferenceParticipants();

      expect(
        participants
            .map(
              (participant) => (
                key: participant.key.value,
                group: participant.group,
                order: participant.order,
                sensitivity: participant.sensitivity,
              ),
            )
            .toList(),
        [
          (
            key: 'customHeaders',
            group: SettingsTransferGroup.network,
            order: 0,
            sensitivity: SettingsTransferSensitivity.credentialBearing,
          ),
          (
            key: 'outputProcessing',
            group: SettingsTransferGroup.outputProcessing,
            order: 0,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
          (
            key: 'fontSizeSettings',
            group: SettingsTransferGroup.other,
            order: 0,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
          (
            key: 'autoRetrySettings',
            group: SettingsTransferGroup.other,
            order: 1,
            sensitivity: SettingsTransferSensitivity.standard,
          ),
        ],
      );
    });

    test('四个 participant 的完整值相同时都不产生 change', () {
      final headers = _headers();
      final output = _outputProcessing();
      final fontSize = _fontSize();
      final retry = _autoRetry();

      expect(
        _createHeadersParticipant().prepareImport(
          local: headers,
          incoming: headers,
        ),
        isNull,
      );
      expect(
        _createOutputProcessingParticipant().prepareImport(
          local: output,
          incoming: output,
        ),
        isNull,
      );
      expect(
        _createFontSizeParticipant().prepareImport(
          local: fontSize,
          incoming: fontSize,
        ),
        isNull,
      );
      expect(
        _createAutoRetryParticipant().prepareImport(
          local: retry,
          incoming: retry,
        ),
        isNull,
      );
    });

    test('非空 Header 和规则整体替换且摘要只暴露动作', () {
      final incomingHeaders = _headers(
        key: 'X-Transfer-Token',
        value: 'test-header-secret',
      );
      final incomingOutput = _outputProcessing(
        pattern: 'test-secret-pattern',
        replacement: 'test-replacement',
      );

      final headerChange = _createHeadersParticipant().prepareImport(
        local: const CustomHeadersConfig(),
        incoming: incomingHeaders,
      );
      final outputChange = _createOutputProcessingParticipant().prepareImport(
        local: const OutputProcessingSettings(),
        incoming: incomingOutput,
      );

      expect(headerChange, isNotNull);
      expect(headerChange!.writeValue, incomingHeaders);
      expect(
        headerChange.summary.action,
        SettingsTransferSummaryAction.replace,
      );
      expect(headerChange.summary.count, isNull);
      expect(
        '${headerChange.summary.label} ${headerChange.summary.trailingText}',
        isNot(contains('test-header-secret')),
      );
      expect(outputChange, isNotNull);
      expect(outputChange!.writeValue, incomingOutput);
      expect(
        outputChange.summary.action,
        SettingsTransferSummaryAction.replace,
      );
      expect(outputChange.summary.count, isNull);
      final outputSummary =
          '${outputChange.summary.label} ${outputChange.summary.trailingText}';
      expect(outputSummary, isNot(contains('test-secret-pattern')));
      expect(outputSummary, isNot(contains('test-replacement')));
    });

    test('空 Header 和规则生成 clear change 而不是 no-op', () {
      final headerChange = _createHeadersParticipant().prepareImport(
        local: _headers(),
        incoming: const CustomHeadersConfig(),
      );
      final outputChange = _createOutputProcessingParticipant().prepareImport(
        local: _outputProcessing(),
        incoming: const OutputProcessingSettings(),
      );

      expect(headerChange, isNotNull);
      expect(headerChange!.writeValue.headers, isEmpty);
      expect(headerChange.summary.action, SettingsTransferSummaryAction.clear);
      expect(headerChange.summary.trailingText, '清空');
      expect(outputChange, isNotNull);
      expect(outputChange!.writeValue.rules, isEmpty);
      expect(outputChange.summary.action, SettingsTransferSummaryAction.clear);
      expect(outputChange.summary.trailingText, '清空');
      expect(
        _createHeadersParticipant().shouldExport(const CustomHeadersConfig()),
        isTrue,
      );
      expect(
        _createOutputProcessingParticipant().shouldExport(
          const OutputProcessingSettings(),
        ),
        isTrue,
      );
    });

    test('字号和自动重试替换完整值', () {
      const incomingFontSize = FontSizeSettings(bodyFontSize: 19.5);
      const incomingRetry = AutoRetrySettings(
        maxJitterSeconds: 7,
        maxRetryCount: 3,
        retryMode: RetryMode.fixedInterval,
        retryOnAbnormalFinishReason: true,
        retryOnTimeout: true,
        timeoutSeconds: 45,
      );

      final fontChange = _createFontSizeParticipant().prepareImport(
        local: const FontSizeSettings(),
        incoming: incomingFontSize,
      );
      final retryChange = _createAutoRetryParticipant().prepareImport(
        local: const AutoRetrySettings(),
        incoming: incomingRetry,
      );

      expect(fontChange, isNotNull);
      expect(fontChange!.writeValue, incomingFontSize);
      expect(fontChange.summary.action, SettingsTransferSummaryAction.replace);
      expect(retryChange, isNotNull);
      expect(retryChange!.writeValue, incomingRetry);
      expect(retryChange.summary.action, SettingsTransferSummaryAction.replace);
    });

    test('四个 map decoder 拒绝非 map 并委托当前模型 fromJson', () {
      final headers = _createHeadersParticipant();
      final output = _createOutputProcessingParticipant();
      final fontSize = _createFontSizeParticipant();
      final retry = _createAutoRetryParticipant();

      expect(headers.decode(_headers().toJson()), _headers());
      expect(output.decode(_outputProcessing().toJson()), _outputProcessing());
      expect(fontSize.decode(_fontSize().toJson()), _fontSize());
      expect(retry.decode(_autoRetry().toJson()), _autoRetry());

      for (final decoder in <Object? Function(Object?)>[
        headers.decode,
        output.decode,
        fontSize.decode,
        retry.decode,
      ]) {
        expect(() => decoder(const []), throwsA(isA<FormatException>()));
        expect(() => decoder(null), throwsA(isA<FormatException>()));
      }
    });

    test('存储 Future 被拒绝时四个 participant 不改变调用方状态', () async {
      var headers = _headers();
      var output = _outputProcessing();
      var fontSize = _fontSize();
      var retry = _autoRetry();
      final originalHeaders = headers;
      final originalOutput = output;
      final originalFontSize = fontSize;
      final originalRetry = retry;
      final rejected = StateError('测试存储拒绝');

      final headerParticipant = CustomHeadersTransferParticipant(
        readLocal: () => headers,
        write: (_) async => throw rejected,
      );
      final outputParticipant = OutputProcessingTransferParticipant(
        readLocal: () => output,
        write: (_) async => throw rejected,
      );
      final fontParticipant = FontSizeSettingsTransferParticipant(
        readLocal: () => fontSize,
        write: (_) async => throw rejected,
      );
      final retryParticipant = AutoRetrySettingsTransferParticipant(
        readLocal: () => retry,
        write: (_) async => throw rejected,
      );

      await expectLater(
        headerParticipant.applyImport(const CustomHeadersConfig()),
        throwsA(same(rejected)),
      );
      await expectLater(
        outputParticipant.applyImport(const OutputProcessingSettings()),
        throwsA(same(rejected)),
      );
      await expectLater(
        fontParticipant.applyImport(const FontSizeSettings(bodyFontSize: 20)),
        throwsA(same(rejected)),
      );
      await expectLater(
        retryParticipant.applyImport(const AutoRetrySettings(maxRetryCount: 2)),
        throwsA(same(rejected)),
      );

      expect(headers, same(originalHeaders));
      expect(output, same(originalOutput));
      expect(fontSize, same(originalFontSize));
      expect(retry, same(originalRetry));
    });
  });
}

void _expectRoundTrip<T>(
  SettingsTransferParticipant<List<T>> participant,
  List<T> value,
) {
  final encoded = participant.encode(value);
  final decoded = participant.decode(jsonDecode(jsonEncode(encoded)));
  expect(decoded, value);
}

void _expectEmptyExport<T>(SettingsTransferParticipant<List<T>> participant) {
  expect(participant.shouldExport(<T>[]), isFalse);
}

void _expectAddSummary<T>(
  SettingsTransferParticipant<List<T>> participant,
  List<T> incoming,
) {
  final change = participant.prepareImport(local: <T>[], incoming: incoming);

  expect(change, isNotNull);
  expect(change!.summary.action, SettingsTransferSummaryAction.add);
  expect(change.summary.count, 1);
  expect(change.writeValue, hasLength(1));
  final summaryText = '${change.summary.label} ${change.summary.trailingText}';
  expect(summaryText, isNot(contains('provider-secret')));
}

List<SettingsTransferParticipant<dynamic>> _createParticipants() {
  return [
    _createProviderParticipant(),
    _createPresetParticipant(),
    _createMemoryParticipant(),
    _createTemplateParticipant(),
    _createSequenceParticipant(),
  ];
}

ModelProviderTransferParticipant _createProviderParticipant() {
  return ModelProviderTransferParticipant(
    readLocal: () => const [],
    write: (_) async {},
  );
}

PresetPromptTransferParticipant _createPresetParticipant() {
  return PresetPromptTransferParticipant(
    readLocal: () => const [],
    write: (_) async {},
  );
}

MemoryPromptTransferParticipant _createMemoryParticipant() {
  return MemoryPromptTransferParticipant(
    readLocal: () => const [],
    write: (_) async {},
  );
}

TemplatePromptTransferParticipant _createTemplateParticipant() {
  return TemplatePromptTransferParticipant(
    readLocal: () => const [],
    write: (_) async {},
  );
}

FixedPromptSequenceTransferParticipant _createSequenceParticipant() {
  return FixedPromptSequenceTransferParticipant(
    readLocal: () => const [],
    write: (_) async {},
  );
}

List<SettingsTransferParticipant<dynamic>> _createPreferenceParticipants() {
  return [
    _createHeadersParticipant(),
    _createOutputProcessingParticipant(),
    _createFontSizeParticipant(),
    _createAutoRetryParticipant(),
  ];
}

CustomHeadersTransferParticipant _createHeadersParticipant() {
  return CustomHeadersTransferParticipant(
    readLocal: _headers,
    write: (_) async {},
  );
}

OutputProcessingTransferParticipant _createOutputProcessingParticipant() {
  return OutputProcessingTransferParticipant(
    readLocal: _outputProcessing,
    write: (_) async {},
  );
}

FontSizeSettingsTransferParticipant _createFontSizeParticipant() {
  return FontSizeSettingsTransferParticipant(
    readLocal: _fontSize,
    write: (_) async {},
  );
}

AutoRetrySettingsTransferParticipant _createAutoRetryParticipant() {
  return AutoRetrySettingsTransferParticipant(
    readLocal: _autoRetry,
    write: (_) async {},
  );
}

CustomHeadersConfig _headers({
  String key = 'X-Test',
  String value = 'test-value',
}) {
  return CustomHeadersConfig(
    headers: [CustomHeaderEntry(key: key, value: value)],
  );
}

OutputProcessingSettings _outputProcessing({
  String pattern = '测试',
  String replacement = '替换',
}) {
  return OutputProcessingSettings(
    rules: [
      OutputRegexRule(
        id: 'rule-1',
        title: '规则 A',
        pattern: pattern,
        replacement: replacement,
        order: 1,
      ),
    ],
  );
}

FontSizeSettings _fontSize() => const FontSizeSettings(bodyFontSize: 18.5);

AutoRetrySettings _autoRetry() => const AutoRetrySettings(
  maxJitterSeconds: 7,
  maxRetryCount: 3,
  retryMode: RetryMode.fixedInterval,
  retryOnAbnormalFinishReason: true,
  retryOnTimeout: true,
  timeoutSeconds: 45,
);

SettingsTransferChange<dynamic>? _providerParticipantNoOpCase() {
  final local = _provider(models: [_model()]);
  final incoming = local.copyWith(
    models: [local.models.single.copyWith(id: 'incoming-model')],
  );
  return _createProviderParticipant().prepareImport(
    local: [local],
    incoming: [incoming],
  );
}

SettingsTransferChange<dynamic>? _presetParticipantNoOpCase(DateTime now) {
  final local = _preset(now);
  final incoming = local.copyWith(
    id: 'incoming-id',
    name: '另一个名字',
    updatedAt: now.add(const Duration(days: 1)),
    messages: [
      local.messages.single.copyWith(id: 'incoming-message', enabled: false),
    ],
  );
  return _createPresetParticipant().prepareImport(
    local: [local],
    incoming: [incoming],
  );
}

SettingsTransferChange<dynamic>? _memoryParticipantNoOpCase(DateTime now) {
  final local = _memory(now);
  final incoming = local.copyWith(
    id: 'incoming-id',
    name: '另一个名字',
    updatedAt: now.add(const Duration(days: 1)),
  );
  return _createMemoryParticipant().prepareImport(
    local: [local],
    incoming: [incoming],
  );
}

SettingsTransferChange<dynamic>? _templateParticipantNoOpCase(DateTime now) {
  final local = _template(now);
  final incoming = local.copyWith(
    id: 'incoming-id',
    title: '另一个标题',
    updatedAt: now.add(const Duration(days: 1)),
  );
  return _createTemplateParticipant().prepareImport(
    local: [local],
    incoming: [incoming],
  );
}

SettingsTransferChange<dynamic>? _sequenceParticipantNoOpCase(DateTime now) {
  final local = _sequence(now);
  final incoming = local.copyWith(
    id: 'incoming-id',
    name: '另一个名称',
    updatedAt: now.add(const Duration(days: 1)),
    steps: [local.steps.single.copyWith(id: 'incoming-step')],
  );
  return _createSequenceParticipant().prepareImport(
    local: [local],
    incoming: [incoming],
  );
}

LlmProviderConfig _provider({
  String id = 'provider-1',
  String name = '服务商',
  String apiUrl = 'https://api.example.com/v1',
  String apiKey = 'provider-secret',
  LlmApiProtocol apiProtocol = LlmApiProtocol.chatCompletions,
  List<LlmProviderModelConfig>? models,
}) {
  return LlmProviderConfig(
    id: id,
    name: name,
    apiUrl: apiUrl,
    apiKey: apiKey,
    apiProtocol: apiProtocol,
    models: models ?? const [],
  );
}

LlmProviderModelConfig _model({
  String id = 'model-1',
  String displayName = '模型',
  String modelName = 'model-name',
}) {
  return LlmProviderModelConfig(
    id: id,
    displayName: displayName,
    modelName: modelName,
    supportsReasoning: false,
  );
}

MemoryPrompt _memory(DateTime updatedAt) {
  return MemoryPrompt(
    id: 'memory-1',
    name: '记忆',
    content: '记忆内容',
    updatedAt: updatedAt,
  );
}

PresetPrompt _preset(DateTime updatedAt) {
  return PresetPrompt(
    id: 'preset-1',
    name: '预设',
    messages: const [
      PromptMessage(
        id: 'message-1',
        title: '系统消息',
        role: PromptMessageRole.system,
        placement: PromptMessagePlacement.before,
        content: '系统内容',
      ),
    ],
    updatedAt: updatedAt,
  );
}

TemplatePrompt _template(DateTime updatedAt) {
  return TemplatePrompt(
    id: 'template-1',
    title: '模板',
    content: '固定正文',
    variables: const [],
    updatedAt: updatedAt,
  );
}

FixedPromptSequence _sequence(DateTime updatedAt) {
  return FixedPromptSequence(
    id: 'sequence-1',
    name: '序列',
    steps: const [
      FixedPromptSequenceStep(id: 'step-1', title: '第一步', content: '第一步内容'),
    ],
    updatedAt: updatedAt,
  );
}
