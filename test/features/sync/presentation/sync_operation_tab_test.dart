import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_operation_tab.dart';

class _SeededSyncClientController extends SyncClientController {
  _SeededSyncClientController(this.seed);

  final SyncClientState seed;

  @override
  SyncClientState build() => seed;
}

void main() {
  // 配对信息属于页面即时状态，不能被同步进度或错误提示替换。
  for (final (phase, paired, phaseText) in [
    (SyncPhase.syncing, true, '正在同步配置...'),
    (SyncPhase.error, true, '同步出错'),
    (SyncPhase.error, false, '同步出错'),
  ]) {
    testWidgets('$phaseText时持续显示${paired ? '已配对状态' : '重新配对指引'}和来源设备', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncClientControllerProvider.overrideWith(
              () => _SeededSyncClientController(
                SyncClientState(
                  phase: phase,
                  isPaired: paired,
                  sourceDeviceName: '工作电脑',
                  server: const DiscoveredServer(
                    deviceName: '工作电脑',
                    ip: '192.168.1.5',
                    httpPort: 8080,
                  ),
                  errorMessage: phase == SyncPhase.error ? '请求失败' : null,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SyncOperationTab())),
        ),
      );

      expect(find.text(phaseText).hitTestable(), findsOneWidget);
      expect(
        find.textContaining(paired ? '已配对' : '尚未配对，请在连接页输入配对码').hitTestable(),
        findsOneWidget,
      );
      expect(find.textContaining('工作电脑').hitTestable(), findsOneWidget);
      if (phase == SyncPhase.error) {
        expect(find.text('请求失败').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
