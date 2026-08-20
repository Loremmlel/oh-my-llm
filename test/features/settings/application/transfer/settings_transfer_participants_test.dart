import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/model_provider_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/preference_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_participant.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_types.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19);

  test('provider 解码器拒绝缺少 apiProtocol', () {
    final participant = _createProviderParticipant();
    final json = _provider().toJson()..remove('apiProtocol');

    expect(
      () => participant.decode([json]),
      throwsA(isA<FormatException>()),
    );
  });

  test('template 解码器拒绝无法编译的模板', () {
    final participant = _createTemplateParticipant();
    final invalid = _template(
      now,
    ).copyWith(content: '{{#if 人称 == "一"}}\n未闭合内容', variables: const []);

    expect(
      () => participant.decode([invalid.toJson()]),
      throwsA(isA<FormatException>()),
    );
  });

  test('集合 participant 保留各自的内容等价规则', () {
    expect(_providerParticipantNoOpCase(), isNull);
    expect(_presetParticipantNoOpCase(now), isNull);
    expect(_memoryParticipantNoOpCase(now), isNull);
    expect(_templateParticipantNoOpCase(now), isNull);
    expect(_sequenceParticipantNoOpCase(now), isNull);
  });

  test('provider participant 合并同凭据服务商并隐藏密钥摘要', () {
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
    final merged = change!.writeValue.single;
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

  test('Header 与输出规则的 replace/clear 摘要不泄露内容', () {
    final incomingHeaders = _headers(
      key: 'X-Transfer-Token',
      value: 'test-header-secret',
    );
    final incomingOutput = _outputProcessing(
      pattern: 'test-secret-pattern',
      replacement: 'test-replacement',
    );
    final headers = _createHeadersParticipant();
    final output = _createOutputProcessingParticipant();

    final headerReplace = headers.prepareImport(
      local: const CustomHeadersConfig(),
      incoming: incomingHeaders,
    );
    final outputReplace = output.prepareImport(
      local: const OutputProcessingSettings(),
      incoming: incomingOutput,
    );
    expect(headerReplace, isNotNull);
    expect(outputReplace, isNotNull);
    expect(
      headerReplace!.summary.action,
      SettingsTransferSummaryAction.replace,
    );
    expect(
      outputReplace!.summary.action,
      SettingsTransferSummaryAction.replace,
    );
    expect(
      '${headerReplace.summary.label} ${headerReplace.summary.trailingText}',
      isNot(contains('test-header-secret')),
    );
    final outputSummary =
        '${outputReplace.summary.label} ${outputReplace.summary.trailingText}';
    expect(outputSummary, isNot(contains('test-secret-pattern')));
    expect(outputSummary, isNot(contains('test-replacement')));

    final headerClear = headers.prepareImport(
      local: incomingHeaders,
      incoming: const CustomHeadersConfig(),
    );
    final outputClear = output.prepareImport(
      local: incomingOutput,
      incoming: const OutputProcessingSettings(),
    );
    expect(headerClear!.summary.action, SettingsTransferSummaryAction.clear);
    expect(outputClear!.summary.action, SettingsTransferSummaryAction.clear);
    expect(headerClear.summary.trailingText, '清空');
    expect(outputClear.summary.trailingText, '清空');
  });

  test('共享 payload decoder 在集合和对象 participant 上拒绝错误形状', () {
    expect(
      () => _createPresetParticipant().decode([1]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => _createHeadersParticipant().decode(const []),
      throwsA(isA<FormatException>()),
    );
  });
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
