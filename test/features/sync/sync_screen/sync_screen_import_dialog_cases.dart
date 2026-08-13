import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/transfer/settings_export_data.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_import_confirm_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import 'sync_screen_test_helpers.dart';

/// 导入动作挂在 [gate] 上的 SyncClientController 替身：
/// 测试先确认 busy 窗口，再通过 gate 结束导入，精确控制 busy 时长。
class _GateSyncClientController extends SyncClientController {
  _GateSyncClientController(this.gate);

  final Completer<bool> gate;

  @override
  SyncClientState build() => connectedSyncState();

  @override
  Future<bool> executeImport() => gate.future;
}

void registerSyncScreenImportDialogTests() {
  group('SyncImportConfirmDialog', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    SettingsExportData buildTestData() {
      return SettingsExportData(
        modelProviders: [
          LlmProviderConfig(
            id: 'pvd-1',
            name: 'OpenAI',
            apiUrl: 'https://api.openai.com/v1',
            apiKey: 'sk-test',
            apiProtocol: LlmApiProtocol.chatCompletions,
            models: [
              LlmProviderModelConfig(
                id: 'model-1',
                displayName: 'GPT-4',
                modelName: 'gpt-4',
                supportsReasoning: false,
              ),
            ],
          ),
        ],
        memoryPrompts: [
          MemoryPrompt(
            id: 'mem-1',
            name: '测试记忆',
            content: '请总结关键事实',
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        presetPrompts: const [],
        templatePrompts: const [],
        fixedPromptSequences: const [],
      );
    }

    testWidgets('显示来源设备名和各分类数量', (tester) async {
      await pumpImportDialog(
        tester,
        preferences: preferences,
        exportData: buildTestData(),
      );

      expect(find.text('确认同步配置'), findsOneWidget);
      expect(find.textContaining('TestPC'), findsOneWidget);
      expect(find.text('LLM 服务商'), findsOneWidget);
      expect(find.text('记忆总结提示词'), findsOneWidget);
    });

    testWidgets('取消按钮关闭对话框', (tester) async {
      await pumpImportDialog(
        tester,
        preferences: preferences,
        exportData: const SettingsExportData(
          modelProviders: [],
          memoryPrompts: [],
          presetPrompts: [],
          templatePrompts: [],
          fixedPromptSequences: [],
        ),
      );
      expect(find.text('确认同步配置'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await settleOverlayTransition(tester);
      expect(find.text('确认同步配置'), findsNothing);
    });

    testWidgets('导入中 Back 不能关闭对话框，失败恢复后可关闭', (tester) async {
      // 导入动作挂在 gate 上：先确认 busy 窗口（导入中 + 取消禁用），
      // 再通过 completeError 让导入失败恢复 busy 状态，精确控制时长。
      final gate = Completer<bool>();
      await pumpTestApp(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => _GateSyncClientController(gate),
          ),
        ],
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SyncImportConfirmDialog(
                exportData: buildTestData(),
                sourceDeviceName: 'TestPC',
              ),
            ),
            child: const Text('打开对话框'),
          ),
        ),
      );
      await tester.tap(find.text('打开对话框'));
      await settleOverlayTransition(tester);

      // 测试数据含服务商 API Key，先勾选敏感凭据确认，导入按钮才可用。
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
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
      expect(find.text('确认同步配置'), findsOneWidget);

      // 导入失败后 busy 恢复为 false，Back 可以关闭。
      gate.completeError(StateError('写入失败'));
      // completeError 的错误沿 await 链以微任务传播，需收敛帧后恢复态才可见。
      await settleAnimatedWidgetTransition(tester);
      expect(find.text('导入失败: Bad state: 写入失败'), findsOneWidget);
      expect(find.text('导入中...'), findsNothing);

      await tester.binding.handlePopRoute();
      await settleOverlayTransition(tester);
      expect(find.text('确认同步配置'), findsNothing);
    });
  });
}
