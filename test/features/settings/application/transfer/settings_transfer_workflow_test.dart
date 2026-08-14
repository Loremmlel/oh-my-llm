import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_workflow.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';

import '../../../../helpers/fixtures.dart';

/// 导出 tab 决策用例：tab、只含该 tab 数据的工作流、只校验其字段的谓词。
typedef ExportTabCase = ({
  SettingsTransferTab tab,
  SettingsTransferWorkflow workflow,
  void Function(SettingsExportData data) verify,
});

void main() {
  // ── 共享类型化数据；TestFixtures 缺失的标量 fixture 在本文件定义 ──
  const provider = LlmProviderConfig(
    id: 'provider-1',
    name: 'OpenAI',
    apiUrl: 'https://api.test',
    apiKey: 'key',
    apiProtocol: LlmApiProtocol.chatCompletions,
  );
  const headers = CustomHeadersConfig(
    headers: [CustomHeaderEntry(key: 'X-Test', value: 'value')],
  );
  const output = OutputProcessingSettings(
    rules: [OutputRegexRule(id: 'rule-1', pattern: 'x')],
  );
  const retry = AutoRetrySettings(maxRetryCount: 2);
  const fontSize = FontSizeSettings(bodyFontSize: 18);

  final preset = TestFixtures.presetPrompt(id: 'preset-1', name: '预设');
  final memory = TestFixtures.memoryPrompt(id: 'memory-1');
  final template = TestFixtures.templatePrompt(id: 'template-1');
  final sequence = TestFixtures.fixedSequence(id: 'sequence-1');

  group('buildExportData 只导出当前 tab 数据', () {
    final exportCases = <ExportTabCase>[
      (
        tab: SettingsTransferTab.providers,
        workflow: SettingsTransferWorkflow(
          readProviders: () => const [provider],
        ),
        verify: (data) {
          expect(data.modelProviders, [provider]);
          expect(data.memoryPrompts, isEmpty);
          expect(data.presetPrompts, isEmpty);
          expect(data.templatePrompts, isEmpty);
          expect(data.fixedPromptSequences, isEmpty);
          expect(data.customHeadersConfig, isNull);
          expect(data.outputProcessingSettings, isNull);
          expect(data.autoRetrySettings, isNull);
          expect(data.fontSizeSettings, isNull);
        },
      ),
      (
        tab: SettingsTransferTab.presets,
        workflow: SettingsTransferWorkflow(readPresetPrompts: () => [preset]),
        verify: (data) {
          expect(data.modelProviders, isEmpty);
          expect(data.memoryPrompts, isEmpty);
          expect(data.presetPrompts, [preset]);
          expect(data.templatePrompts, isEmpty);
          expect(data.fixedPromptSequences, isEmpty);
          expect(data.customHeadersConfig, isNull);
          expect(data.outputProcessingSettings, isNull);
          expect(data.autoRetrySettings, isNull);
          expect(data.fontSizeSettings, isNull);
        },
      ),
      (
        tab: SettingsTransferTab.prompts,
        workflow: SettingsTransferWorkflow(
          readMemoryPrompts: () => [memory],
          readTemplatePrompts: () => [template],
          readSequences: () => [sequence],
        ),
        verify: (data) {
          expect(data.modelProviders, isEmpty);
          expect(data.memoryPrompts, [memory]);
          expect(data.presetPrompts, isEmpty);
          expect(data.templatePrompts, [template]);
          expect(data.fixedPromptSequences, [sequence]);
          expect(data.customHeadersConfig, isNull);
          expect(data.outputProcessingSettings, isNull);
          expect(data.autoRetrySettings, isNull);
          expect(data.fontSizeSettings, isNull);
        },
      ),
      (
        tab: SettingsTransferTab.network,
        workflow: SettingsTransferWorkflow(readHeaders: () => headers),
        verify: (data) {
          expect(data.modelProviders, isEmpty);
          expect(data.memoryPrompts, isEmpty);
          expect(data.presetPrompts, isEmpty);
          expect(data.templatePrompts, isEmpty);
          expect(data.fixedPromptSequences, isEmpty);
          expect(data.customHeadersConfig, headers);
          expect(data.outputProcessingSettings, isNull);
          expect(data.autoRetrySettings, isNull);
          expect(data.fontSizeSettings, isNull);
        },
      ),
      (
        tab: SettingsTransferTab.outputProcessing,
        workflow: SettingsTransferWorkflow(readOutputProcessing: () => output),
        verify: (data) {
          expect(data.modelProviders, isEmpty);
          expect(data.memoryPrompts, isEmpty);
          expect(data.presetPrompts, isEmpty);
          expect(data.templatePrompts, isEmpty);
          expect(data.fixedPromptSequences, isEmpty);
          expect(data.customHeadersConfig, isNull);
          expect(data.outputProcessingSettings, output);
          expect(data.autoRetrySettings, isNull);
          expect(data.fontSizeSettings, isNull);
        },
      ),
      (
        tab: SettingsTransferTab.other,
        workflow: SettingsTransferWorkflow(
          readAutoRetry: () => retry,
          readFontSize: () => fontSize,
        ),
        verify: (data) {
          expect(data.modelProviders, isEmpty);
          expect(data.memoryPrompts, isEmpty);
          expect(data.presetPrompts, isEmpty);
          expect(data.templatePrompts, isEmpty);
          expect(data.fixedPromptSequences, isEmpty);
          expect(data.customHeadersConfig, isNull);
          expect(data.outputProcessingSettings, isNull);
          expect(data.autoRetrySettings, retry);
          expect(data.fontSizeSettings, fontSize);
        },
      ),
    ];

    for (final testCase in exportCases) {
      test('${testCase.tab.name} 只导出当前 tab 数据', () {
        final result = testCase.workflow.buildExportData(testCase.tab);
        expect(result, isNotNull);
        testCase.verify(result!);
      });
    }
  });

  group('空工作流下各 tab 导出', () {
    final emptyWorkflow = SettingsTransferWorkflow();
    for (final tab in [
      SettingsTransferTab.providers,
      SettingsTransferTab.presets,
      SettingsTransferTab.prompts,
      SettingsTransferTab.network,
      SettingsTransferTab.outputProcessing,
    ]) {
      test('${tab.name} 无内容时导出 null', () {
        expect(emptyWorkflow.buildExportData(tab), isNull);
      });
    }
    test('other 无内容时仍导出当前标量默认值而非 null', () {
      final result = emptyWorkflow.buildExportData(SettingsTransferTab.other);
      expect(result, isNotNull);
      expect(result!.autoRetrySettings, const AutoRetrySettings());
      expect(result.fontSizeSettings, const FontSizeSettings());
    });
  });

  group('buildSinglePresetExportData 只导出指定预设', () {
    test('导出数据只含该预设，其余列表为空且可被原样解码回来', () {
      // 默认构造：该方法不读任何注入的 controller，故不需要 seed 任何 reader。
      final workflow = SettingsTransferWorkflow();
      // 用带显式 title 的消息构造预设：PresetPrompt.fromJson 对空 title 会按
      // placement+role 回退填充 ([]（副本 N）），那是不保证 round-trip 等价的
      // 既有解码行为，不属于本次契约；显式 title 让解码可完整还原。
      final preset = TestFixtures.presetPrompt(
        id: 'preset-1',
        name: '代码助手',
        messages: [
          TestFixtures.promptMessage(
            id: 'message-1',
            role: PromptMessageRole.user,
            title: '前置要求',
            content: '请优先关注实现细节。',
            placement: PromptMessagePlacement.before,
          ),
        ],
      );

      final data = workflow.buildSinglePresetExportData(preset);

      expect(data.presetPrompts, [preset]);
      expect(data.modelProviders, isEmpty);
      expect(data.memoryPrompts, isEmpty);
      expect(data.templatePrompts, isEmpty);
      expect(data.fixedPromptSequences, isEmpty);
      expect(data.autoRetrySettings, isNull);
      expect(data.customHeadersConfig, isNull);
      expect(data.fontSizeSettings, isNull);
      expect(data.outputProcessingSettings, isNull);

      // round-trip：导出 JSON 再解码，预设应回到等同对象，证明产物能被另一台
      // 设备的导入路径原样识别（identifier + formatVersion 由 codec 负责）。
      final decoded = SettingsExportData.tryParseJson(data.toJsonString());
      expect(decoded, isNotNull);
      expect(decoded!.presetPrompts, [preset]);
    });
  });

  group('prepareImport 决策', () {
    test('剪贴板文本为 null 时报告 invalidClipboard', () {
      final workflow = SettingsTransferWorkflow();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.providers,
        clipboardText: null,
      );
      expect(result.kind, SettingsImportPreparationKind.invalidClipboard);
    });

    test('未来 formatVersion 快照报告 unsupportedVersion', () {
      // 未来格式边界：版本号高于当前格式，解码在版本检查处拒绝，顶层列表仅供解析结构参考。
      final futureSnapshot = jsonEncode({
        'identifier': SettingsExportData.identifier,
        'formatVersion': SettingsExportData.formatVersion + 1,
        'modelProviders': <Object>[],
        'memoryPrompts': <Object>[],
        'presetPrompts': <Object>[],
        'templatePrompts': <Object>[],
        'fixedPromptSequences': <Object>[],
      });
      final workflow = SettingsTransferWorkflow();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.providers,
        clipboardText: futureSnapshot,
      );
      expect(result.kind, SettingsImportPreparationKind.unsupportedVersion);
    });

    test('providers tab 导入 preset 数据时报告 tabMismatch', () {
      final workflow = SettingsTransferWorkflow();
      final text = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: [preset],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      ).toJsonString();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.providers,
        clipboardText: text,
      );
      expect(result.kind, SettingsImportPreparationKind.tabMismatch);
    });

    test('presets tab 导入与本地一致的 preset 时报告 noNewItems', () {
      final workflow = SettingsTransferWorkflow(
        readPresetPrompts: () => [preset],
      );
      final text = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: [preset],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      ).toJsonString();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.presets,
        clipboardText: text,
      );
      expect(result.kind, SettingsImportPreparationKind.noNewItems);
    });

    test('presets tab 导入新 preset 时报告 ready 且数据只含该 preset', () {
      final workflow = SettingsTransferWorkflow();
      final text = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: [preset],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      ).toJsonString();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.presets,
        clipboardText: text,
      );
      expect(result.kind, SettingsImportPreparationKind.ready);
      expect(result.data, isNotNull);
      expect(result.data!.presetPrompts, [preset]);
    });

    test('network tab 导入自定义 Header 时报告 ready', () {
      final workflow = SettingsTransferWorkflow();
      final text = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
        customHeadersConfig: headers,
      ).toJsonString();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.network,
        clipboardText: text,
      );
      expect(result.kind, SettingsImportPreparationKind.ready);
      expect(result.data, isNotNull);
      expect(result.data!.customHeadersConfig, headers);
    });

    test('outputProcessing tab 导入输出规则时报告 ready', () {
      final workflow = SettingsTransferWorkflow();
      final text = SettingsExportData(
        modelProviders: const [],
        memoryPrompts: const [],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
        outputProcessingSettings: output,
      ).toJsonString();
      final result = workflow.prepareImport(
        tab: SettingsTransferTab.outputProcessing,
        clipboardText: text,
      );
      expect(result.kind, SettingsImportPreparationKind.ready);
      expect(result.data, isNotNull);
      expect(result.data!.outputProcessingSettings, output);
    });

    group('prompts tab 三个 OR 分支各自报告 ready', () {
      test('仅记忆提示词', () {
        final workflow = SettingsTransferWorkflow();
        final text = SettingsExportData(
          modelProviders: const [],
          memoryPrompts: [memory],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
        ).toJsonString();
        final result = workflow.prepareImport(
          tab: SettingsTransferTab.prompts,
          clipboardText: text,
        );
        expect(result.kind, SettingsImportPreparationKind.ready);
        expect(result.data, isNotNull);
        expect(result.data!.memoryPrompts, [memory]);
      });

      test('仅模板提示词', () {
        final workflow = SettingsTransferWorkflow();
        final text = SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: [template],
          fixedPromptSequences: const [],
        ).toJsonString();
        final result = workflow.prepareImport(
          tab: SettingsTransferTab.prompts,
          clipboardText: text,
        );
        expect(result.kind, SettingsImportPreparationKind.ready);
        expect(result.data, isNotNull);
        expect(result.data!.templatePrompts, [template]);
      });

      test('仅固定序列', () {
        final workflow = SettingsTransferWorkflow();
        final text = SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: [sequence],
        ).toJsonString();
        final result = workflow.prepareImport(
          tab: SettingsTransferTab.prompts,
          clipboardText: text,
        );
        expect(result.kind, SettingsImportPreparationKind.ready);
        expect(result.data, isNotNull);
        expect(result.data!.fixedPromptSequences, [sequence]);
      });
    });

    group('other tab 两个 OR 分支各自报告 ready', () {
      test('仅重试设置', () {
        final workflow = SettingsTransferWorkflow();
        final text = SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
          autoRetrySettings: retry,
        ).toJsonString();
        final result = workflow.prepareImport(
          tab: SettingsTransferTab.other,
          clipboardText: text,
        );
        expect(result.kind, SettingsImportPreparationKind.ready);
        expect(result.data, isNotNull);
        expect(result.data!.autoRetrySettings, retry);
      });

      test('仅正文字号', () {
        final workflow = SettingsTransferWorkflow();
        final text = SettingsExportData(
          modelProviders: const [],
          memoryPrompts: const [],
          presetPrompts: const [],
          templatePrompts: const [],
          fixedPromptSequences: const [],
          fontSizeSettings: fontSize,
        ).toJsonString();
        final result = workflow.prepareImport(
          tab: SettingsTransferTab.other,
          clipboardText: text,
        );
        expect(result.kind, SettingsImportPreparationKind.ready);
        expect(result.data, isNotNull);
        expect(result.data!.fontSizeSettings, fontSize);
      });
    });
  });
}
