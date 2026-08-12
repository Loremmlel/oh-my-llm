import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/fixed_prompt_sequences_controller.dart';
import 'package:oh_my_llm/features/settings/application/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/memory_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/application/settings_import_executor.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/import_confirm_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';

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
    apiProtocol: LlmApiProtocol.chatCompletions,
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

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('打开'));
  // 等待 AlertDialog 入场动画结束。
  await settleOverlayTransition(tester);
  expect(find.text('检测到配置导入数据'), findsOneWidget);
}

/// 所有写入都挂在 [gate] 上的导入目标：测试先确认 busy 窗口，
/// 再通过完成/失败 gate 让导入流程结束，精确控制 busy 时长。
final class _GateImportTargets implements SettingsImportTargets {
  const _GateImportTargets(this.gate);

  final Completer<void> gate;

  Future<void> _awaitGate() async {
    await gate.future;
  }

  @override
  Future<void> mergeImportedProviders(List<LlmProviderConfig> value) =>
      _awaitGate();
  @override
  Future<void> saveAutoRetrySettings(AutoRetrySettings value) => _awaitGate();
  @override
  Future<void> saveCustomHeaders(CustomHeadersConfig value) => _awaitGate();
  @override
  Future<void> saveFontSize(FontSizeSettings value) => _awaitGate();
  @override
  Future<void> saveOutputProcessing(OutputProcessingSettings value) =>
      _awaitGate();
  @override
  Future<void> upsertFixedPromptSequences(List<FixedPromptSequence> value) =>
      _awaitGate();
  @override
  Future<void> upsertMemoryPrompts(List<MemoryPrompt> value) => _awaitGate();
  @override
  Future<void> upsertPresetPrompts(List<PresetPrompt> value) => _awaitGate();
  @override
  Future<void> upsertTemplatePrompts(List<TemplatePrompt> value) =>
      _awaitGate();
}

final class _FailingImportTargets implements SettingsImportTargets {
  const _FailingImportTargets();

  Never _fail() => throw StateError('写入失败');

  @override
  Future<void> mergeImportedProviders(List<LlmProviderConfig> value) async =>
      _fail();
  @override
  Future<void> saveAutoRetrySettings(AutoRetrySettings value) async => _fail();
  @override
  Future<void> saveCustomHeaders(CustomHeadersConfig value) async => _fail();
  @override
  Future<void> saveFontSize(FontSizeSettings value) async => _fail();
  @override
  Future<void> saveOutputProcessing(OutputProcessingSettings value) async =>
      _fail();
  @override
  Future<void> upsertFixedPromptSequences(
    List<FixedPromptSequence> value,
  ) async => _fail();
  @override
  Future<void> upsertMemoryPrompts(List<MemoryPrompt> value) async => _fail();
  @override
  Future<void> upsertPresetPrompts(List<PresetPrompt> value) async => _fail();
  @override
  Future<void> upsertTemplatePrompts(List<TemplatePrompt> value) async =>
      _fail();
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
      SettingsExportData data, {
      List<dynamic> extraOverrides = const [],
    }) async {
      await pumpTestApp(
        tester,
        preferences: preferences,
        extraOverrides: extraOverrides,
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

    testWidgets('点"导入"后写入所有配置分类', (tester) async {
      final container = await pumpHost(tester, _buildFullData());
      await _openDialog(tester);

      await tester.tap(find.text('导入'));
      // 导入 Future 完成后对话框出场，一次覆盖两者
      await settleOverlayTransition(tester);

      expect(container.read(llmProviderConfigsProvider).length, 1);
      expect(container.read(llmProviderConfigsProvider).first.id, 'provider-1');
      expect(container.read(memoryPromptsProvider).length, 1);
      expect(container.read(memoryPromptsProvider).first.id, 'mem-1');
      expect(container.read(presetPromptsProvider).length, 1);
      expect(container.read(templatePromptsProvider).length, 1);
      expect(container.read(fixedPromptSequencesProvider).length, 1);
      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 20);
      expect(settings.maxRetryCount, 5);
    });

    testWidgets('点"取消"后所有 provider 状态不变', (tester) async {
      final container = await pumpHost(tester, _buildFullData());
      await _openDialog(tester);

      await tester.tap(find.text('取消'));
      await settleOverlayTransition(tester);

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

    testWidgets('导入失败时保持对话框打开并恢复导入操作', (tester) async {
      await pumpTestApp(
        tester,
        preferences: preferences,
        extraOverrides: [
          settingsImportExecutorProvider.overrideWithValue(
            SettingsImportExecutor(targets: const _FailingImportTargets()),
          ),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    ImportConfirmDialog(exportData: _buildFullData()),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      await tester.tap(find.text('导入'));
      // 导入失败不走对话框出场，错误状态单帧渲染即可
      await tester.pump();

      expect(find.text('检测到配置导入数据'), findsOneWidget);
      expect(find.text('导入失败：Bad state: 写入失败'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsNothing);
    });

    testWidgets('导入中 Back 不能关闭对话框，失败恢复后可关闭', (tester) async {
      // 导入动作挂在 gate 上：先确认 busy 窗口（导入中 + 取消禁用），
      // 再通过 completeError 让导入失败恢复 busy 状态，精确控制时长。
      final gate = Completer<void>();
      await pumpHost(
        tester,
        _buildFullData(),
        extraOverrides: [
          settingsImportExecutorProvider.overrideWithValue(
            SettingsImportExecutor(targets: _GateImportTargets(gate)),
          ),
        ],
      );
      await _openDialog(tester);

      await tester.tap(find.text('导入'));
      // _isImporting 置 true 是同步状态，单帧渲染即可
      await tester.pump();

      expect(find.text('导入中...'), findsOneWidget);
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '取消'),
      );
      expect(cancelButton.onPressed, isNull);

      // busy 期间 system Back 不能关闭对话框（PopScope canPop=false）。
      await tester.binding.handlePopRoute();
      // 等退场动画收敛：若路由真的在退场，动画结束后对话框必然消失，
      // 单帧 pump 只会停在退场中途、树里仍有对话框，无法区分二者。
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsOneWidget);

      // 导入失败后 busy 恢复为 false，Back 可以关闭。
      gate.completeError(StateError('写入失败'));
      // completeError 的错误沿 await 链以微任务传播，且错误气泡首次插入走
      // AnimatedList initialItemCount，需收敛帧后文案才可见。
      await settleAnimatedWidgetTransition(tester);
      expect(find.text('导入失败：Bad state: 写入失败'), findsOneWidget);
      expect(find.text('导入中...'), findsNothing);

      await tester.binding.handlePopRoute();
      await settleOverlayTransition(tester);
      expect(find.text('检测到配置导入数据'), findsNothing);
    });
  });
}
