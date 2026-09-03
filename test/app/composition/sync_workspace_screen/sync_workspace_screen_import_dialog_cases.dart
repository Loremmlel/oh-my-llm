import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_import_confirm_dialog.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';
import 'sync_workspace_screen_test_helpers.dart';
import '../../../features/sync/application/sync_test_fakes.dart';

/// 导入动作挂在 [gate] 上的 SyncClientController 替身：
/// 测试先确认 busy 窗口，再通过 gate 结束导入，精确控制 busy 时长。
class _GateSyncClientController extends SyncClientController {
  _GateSyncClientController(this.gate);

  final Completer<SettingsSyncImportExecutionResult> gate;

  @override
  SyncClientState build() => connectedSyncState();

  @override
  Future<SettingsSyncImportExecutionResult> executePreparedImport({
    required bool confirmedSensitive,
  }) => gate.future;
}

class _PreparedSyncClientController extends SyncClientController {
  _PreparedSyncClientController(this.preparedImport);

  final SettingsSyncPreparedImport preparedImport;

  @override
  SyncClientState build() => SyncClientState(
    phase: SyncPhase.received,
    preparedImport: preparedImport,
  );
}

void registerSyncScreenImportDialogTests() {
  group('SyncImportConfirmDialog', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    SettingsSyncPreparedImport buildTestData() =>
        ScriptedSettingsSyncPreparedImport(
          summaries: const [
            SettingsSyncSummaryItem(label: 'LLM 服务商', trailingText: '新增 1 项'),
            SettingsSyncSummaryItem(label: '记忆总结提示词', trailingText: '新增 1 项'),
          ],
          containsSensitive: true,
        );

    testWidgets('导入中 Back 不能关闭对话框，失败恢复后可关闭', (tester) async {
      // 导入动作挂在 gate 上：先确认 busy 窗口（导入中 + 取消禁用），
      // 再通过 completeError 让导入失败恢复 busy 状态，精确控制时长。
      final gate = Completer<SettingsSyncImportExecutionResult>();
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
                preparedImport: buildTestData(),
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
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(find.text('确认同步配置'), findsOneWidget);

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
      expect(find.text('导入未完成，请重试'), findsOneWidget);
      expect(find.text('导入中...'), findsNothing);

      await tester.binding.handlePopRoute();
      await settleOverlayTransition(tester);
      expect(find.text('确认同步配置'), findsNothing);
    });

    testWidgets('预处理导入对话框把敏感确认传给控制器', (tester) async {
      final prepared = ScriptedSettingsSyncPreparedImport(
        summaries: const [
          SettingsSyncSummaryItem(label: '测试设置', trailingText: '替换'),
        ],
        containsSensitive: true,
      );

      await pumpTestApp(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => _PreparedSyncClientController(prepared),
          ),
        ],
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SyncImportConfirmDialog(
                preparedImport: prepared,
                sourceDeviceName: 'TestPC',
              ),
            ),
            child: const Text('打开对话框'),
          ),
        ),
      );
      await tester.tap(find.text('打开对话框'));
      await settleOverlayTransition(tester);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('导入'));
      await tester.pump();
      await settleAnimatedWidgetTransition(tester);
      expect(prepared.requestedSensitiveConfirmation, isTrue);
      expect(find.text('确认同步配置'), findsNothing);
    });
  });
}
