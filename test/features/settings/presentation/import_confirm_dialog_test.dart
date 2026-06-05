import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/import_confirm_dialog.dart';

import '../../../helpers/test_harness.dart';

// ── 工厂函数 ────────────────────────────────────────────────────────────────

LlmProviderConfig _provider({
  String id = 'provider-1',
  String name = 'OpenAI',
  String apiUrl = 'https://api.openai.com/v1/chat/completions',
  String apiKey = 'sk-test',
}) {
  return LlmProviderConfig(
    id: id,
    name: name,
    apiUrl: apiUrl,
    apiKey: apiKey,
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

const AutoRetrySettings _autoRetry = AutoRetrySettings(
  maxJitterSeconds: 20,
  maxRetryCount: 5,
);

SettingsExportData _buildFullData() {
  return SettingsExportData(
    modelProviders: [_provider()],
    memoryPrompts: [_memory()],
    presetPrompts: [_preset()],
    templatePrompts: [_template()],
    fixedPromptSequences: [_sequence()],
    autoRetrySettings: _autoRetry,
  );
}

Future<void> _openDialog(WidgetTester tester, SettingsExportData data) async {
  await tester.tap(find.text('打开'));
  await tester.pump();
  // 等待 AlertDialog 入场。
  await tester.pumpAndSettle();
  expect(find.byType(ImportConfirmDialog), findsOneWidget);
}

// ── 测试主体 ────────────────────────────────────────────────────────────────

void main() {
  group('ImportConfirmDialog', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      SettingsExportData data,
    ) async {
      await pumpTestApp(
        tester,
        preferences: preferences,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => ImportConfirmDialog(exportData: data),
                  );
                },
                child: const Text('打开'),
              ),
            );
          },
        ),
      );

      // 借助 host 的 Element 取到 ProviderScope 的 container 用于断言。
      final element = tester.element(find.text('打开'));
      return ProviderScope.containerOf(element);
    }

    testWidgets('点"导入"后写入 providers / memory / preset / template / sequence',
        (tester) async {
      final container = await pumpHost(tester, _buildFullData());
      await _openDialog(tester, _buildFullData());

      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();

      expect(
        container.read(llmProviderConfigsProvider).length,
        1,
      );
      expect(
        container.read(llmProviderConfigsProvider).first.id,
        'provider-1',
      );
      expect(container.read(memoryPromptsProvider).length, 1);
      expect(container.read(memoryPromptsProvider).first.id, 'mem-1');
      expect(container.read(presetPromptsProvider).length, 1);
      expect(container.read(templatePromptsProvider).length, 1);
      expect(container.read(fixedPromptSequencesProvider).length, 1);
    });

    // 已知缺陷：deduplicator 丢弃 autoRetrySettings。
    // 本用例验证 ImportConfirmDialog 本身写入逻辑是否正确处理 autoRetrySettings。
    // 由于对话框直接从 exportData 读取，不经过 deduplicator，预期会通过。
    // 真正的 bug 在 SettingsImportDeduplicator.deduplicate() 返回时未传递 autoRetrySettings，
    // 后续在 settings_import_deduplicator_test.dart 中用 @Skip 标记该路径。
    testWidgets('点"导入"后 autoRetrySettingsProvider 写入 autoRetrySettings',
        (tester) async {
      final container = await pumpHost(tester, _buildFullData());
      await _openDialog(tester, _buildFullData());

      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 20);
      expect(settings.maxRetryCount, 5);
    });

    testWidgets('点"取消"后所有 provider 状态不变', (tester) async {
      final container = await pumpHost(tester, _buildFullData());
      await _openDialog(tester, _buildFullData());

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(container.read(llmProviderConfigsProvider), isEmpty);
      expect(container.read(memoryPromptsProvider), isEmpty);
      expect(container.read(presetPromptsProvider), isEmpty);
      expect(container.read(templatePromptsProvider), isEmpty);
      expect(container.read(fixedPromptSequencesProvider), isEmpty);
      expect(
        container.read(autoRetrySettingsProvider),
        const AutoRetrySettings(),
      );
    });
  });
}
