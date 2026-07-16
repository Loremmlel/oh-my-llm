import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider({String id = 'provider-1'}) {
  return LlmProviderConfig(
    id: id,
    name: 'OpenAI',
    apiUrl: 'https://api.openai.com/v1/chat/completions',
    apiKey: 'sk-test',
    models: const [],
  );
}

MemoryPrompt _memory({String id = 'mem-1'}) {
  return MemoryPrompt(
    id: id,
    name: '测试记忆',
    content: '请总结关键事实。',
    updatedAt: DateTime(2026, 1, 1),
  );
}

PresetPrompt _preset({String id = 'preset-1'}) {
  return PresetPrompt(
    id: id,
    name: '测试预设',
    messages: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

TemplatePrompt _template({String id = 'tpl-1'}) {
  return TemplatePrompt(
    id: id,
    title: '测试模板',
    content: '正文：{{body}}',
    variables: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

FixedPromptSequence _sequence({String id = 'seq-1'}) {
  return FixedPromptSequence(
    id: id,
    name: '测试序列',
    steps: const [],
    updatedAt: DateTime(2026, 1, 1),
  );
}

SettingsExportData _buildFullData() {
  return SettingsExportData(
    modelProviders: [_provider()],
    memoryPrompts: [_memory()],
    presetPrompts: [_preset()],
    templatePrompts: [_template()],
    fixedPromptSequences: [_sequence()],
    autoRetrySettings: const AutoRetrySettings(
      maxJitterSeconds: 20,
      maxRetryCount: 5,
    ),
    customHeadersConfig: const CustomHeadersConfig(
      headers: [
        CustomHeaderEntry(key: 'X-Test', value: 'test-value'),
      ],
    ),
  );
}

SettingsExportData _buildEmptyData() {
  return const SettingsExportData(
    modelProviders: [],
    memoryPrompts: [],
    presetPrompts: [],
    templatePrompts: [],
    fixedPromptSequences: [],
  );
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('SettingsExportData', () {
    test('toJsonString 输出包含 identifier 和 version', () {
      final data = _buildEmptyData();
      final jsonMap = jsonDecode(data.toJsonString()) as Map<String, dynamic>;

      expect(jsonMap['identifier'], SettingsExportData.identifier);
      expect(jsonMap['identifier'], 'shikiyuzu-oh-my-llm');
      expect(jsonMap['version'], SettingsExportData.formatVersion);
      expect(jsonMap['version'], 5);
    });

    test('toJsonString 再 tryParseJson 可还原完整数据（7 个分类）', () {
      final original = _buildFullData();
      final parsed = SettingsExportData.tryParseJson(original.toJsonString());

      expect(parsed, isNotNull);
      expect(parsed!.modelProviders.length, 1);
      expect(parsed.modelProviders.first.id, 'provider-1');
      expect(parsed.memoryPrompts.length, 1);
      expect(parsed.memoryPrompts.first.id, 'mem-1');
      expect(parsed.presetPrompts.length, 1);
      expect(parsed.presetPrompts.first.id, 'preset-1');
      expect(parsed.templatePrompts.length, 1);
      expect(parsed.templatePrompts.first.id, 'tpl-1');
      expect(parsed.fixedPromptSequences.length, 1);
      expect(parsed.fixedPromptSequences.first.id, 'seq-1');
      expect(parsed.autoRetrySettings, isNotNull);
      expect(parsed.autoRetrySettings!.maxJitterSeconds, 20);
      expect(parsed.autoRetrySettings!.maxRetryCount, 5);
      expect(parsed.customHeadersConfig, isNotNull);
      expect(parsed.customHeadersConfig!.headers.length, 1);
      expect(parsed.customHeadersConfig!.headers.first.key, 'X-Test');
      expect(parsed.customHeadersConfig!.headers.first.value, 'test-value');
    });

    test('tryParseJson 在 null / 空字符串 / 非法 JSON / 错误 identifier 时返回 null',
        () {
      expect(SettingsExportData.tryParseJson(null), isNull);
      expect(SettingsExportData.tryParseJson(''), isNull);
      expect(SettingsExportData.tryParseJson('   '), isNull);
      expect(SettingsExportData.tryParseJson('not a json'), isNull);

      // identifier 不匹配
      final wrongId = jsonEncode({
        'identifier': 'wrong-id',
        'version': SettingsExportData.formatVersion,
        'modelProviders': <Map<String, dynamic>>[],
      });
      expect(SettingsExportData.tryParseJson(wrongId), isNull);
    });

    test('hasContent 在全空时为 false，在任一分类非空（含 autoRetry / customHeaders）时为 true', () {
      expect(_buildEmptyData().hasContent, isFalse);

      expect(
        SettingsExportData(
          modelProviders: [_provider()],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
        ).hasContent,
        isTrue,
      );

      expect(
        SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
          autoRetrySettings: const AutoRetrySettings(),
        ).hasContent,
        isTrue,
      );

      expect(
        const SettingsExportData(
          modelProviders: [],
          memoryPrompts: [],
          presetPrompts: [],
          templatePrompts: [],
          fixedPromptSequences: [],
          customHeadersConfig: CustomHeadersConfig(
            headers: [CustomHeaderEntry(key: 'X-Test', value: 'v')],
          ),
        ).hasContent,
        isTrue,
      );
    });

    test('outputProcessingSettings 可 round-trip 且驱动 hasContent', () {
      const data = SettingsExportData(
        modelProviders: [],
        memoryPrompts: [],
        presetPrompts: [],
        templatePrompts: [],
        fixedPromptSequences: [],
        outputProcessingSettings: OutputProcessingSettings(
          rules: [
            OutputRegexRule(
              id: 'rule-1',
              title: '过滤极其',
              pattern: '极其',
              replacement: '',
              order: 0,
            ),
          ],
        ),
      );

      expect(data.hasContent, isTrue);

      final parsed = SettingsExportData.tryParseJson(data.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.outputProcessingSettings, isNotNull);
      expect(parsed.outputProcessingSettings!.rules.length, 1);
      expect(parsed.outputProcessingSettings!.rules.first.pattern, '极其');
      expect(parsed.outputProcessingSettings!.rules.first.title, '过滤极其');
    });
  });
}
