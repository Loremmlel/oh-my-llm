import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_operation_tab.dart';

import '../../../helpers/widget_test_animation.dart';
import 'sync_screen_test_helpers.dart';

void registerSyncScreenRenderTests() {
  group('SyncScreen 渲染', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      RecordingMediaBrowserController.latest = null;
      RecordingMediaBrowserController.lastState = null;
      RecordingMediaBrowserController.totalInitCount = 0;
      RecordingShufflePlaybackController.latest = null;
      RecordingShufflePlaybackController.lastState = null;
    });

    testWidgets('渲染标题、标签页与模式选择器，默认显示连接标签页内容', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      expect(find.text('局域网同步'), findsOneWidget);
      expect(find.text('连接'), findsAtLeast(1));
      expect(find.text('同步'), findsAtLeast(1));
      expect(find.text('作为客户端'), findsOneWidget);
      expect(find.text('作为服务端'), findsOneWidget);
      // 默认连接标签页：显示服务端发现入口，不显示服务端广播面板
      expect(find.text('发现服务端'), findsWidgets);
      expect(find.text('服务端广播'), findsNothing);
    });

    testWidgets('切换到服务端模式显示服务端面板', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      await tester.tap(find.text('作为服务端'));
      await tester.pump();

      expect(find.text('服务端广播'), findsOneWidget);
      expect(find.text('发现服务端'), findsNothing);
    });

    testWidgets('配对失败后保留服务端连接和重新配对入口', (tester) async {
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(
              SyncClientState(
                phase: SyncPhase.error,
                server: const DiscoveredServer(
                  deviceName: 'Test PC',
                  ip: '192.168.1.2',
                  httpPort: 8080,
                  serverId: 'server-id',
                  protocolRange: SyncProtocolRange.local,
                ),
                sourceDeviceName: 'Test PC',
                errorMessage: '配对失败，请重新生成配对码后重试',
              ),
            ),
          ),
        ],
      );

      expect(find.text('输入配对码'), findsOneWidget);
      expect(find.text('断开连接'), findsOneWidget);
      expect(find.text('重新搜索'), findsOneWidget);
    });

    testWidgets('修改同步类别不会复用旧的一致性结果弹出消息', (tester) async {
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(
              SyncClientState(
                phase: SyncPhase.noNewData,
                server: const DiscoveredServer(
                  deviceName: 'Test PC',
                  ip: '192.168.1.2',
                  httpPort: 8080,
                  serverId: 'server-id',
                  protocolRange: SyncProtocolRange.local,
                ),
                sourceDeviceName: 'Test PC',
                isPaired: true,
              ),
            ),
          ),
        ],
      );

      await tester.tap(find.text('同步').last);
      await settleTabTransition(tester);
      await tester.tap(find.text(SyncCategory.presets.label));
      await tester.pump();

      expect(find.text('远端配置与本机完全一致，无需导入'), findsNothing);
    });

    testWidgets('Android 离开媒体 Tab 重置并重新进入时重新加载根目录', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(connectedSyncState()),
          ),
          mediaBrowserControllerProvider.overrideWith(
            RecordingMediaBrowserController.new,
          ),
          shufflePlaybackControllerProvider.overrideWith(
            RecordingShufflePlaybackController.new,
          ),
        ],
      );

      await tester.tap(find.text('媒体'));
      await settleTabTransition(tester);
      expect(RecordingMediaBrowserController.lastState!.server, isNotNull);
      expect(RecordingMediaBrowserController.totalInitCount, 1);
      RecordingShufflePlaybackController.latest!.activateForTest();

      await tester.tap(find.text('连接'));
      await settleTabTransition(tester);
      expect(RecordingMediaBrowserController.lastState, MediaBrowserState());
      expect(
        RecordingShufflePlaybackController.lastState,
        const ShufflePlaybackIdle(),
      );

      await tester.tap(find.text('媒体'));
      await settleTabTransition(tester);
      expect(RecordingMediaBrowserController.totalInitCount, 2);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android 初始媒体 Tab 会初始化浏览会话', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await preferences.setInt('sync.tab.last_index', 2);
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(connectedSyncState()),
          ),
          mediaBrowserControllerProvider.overrideWith(
            RecordingMediaBrowserController.new,
          ),
        ],
      );

      expect(find.text('媒体'), findsAtLeast(1));
      expect(RecordingMediaBrowserController.totalInitCount, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('断开后连接标签页显示断开文案，同步标签页显示占位而非通用未连接文案', (tester) async {
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(
              SyncClientState(
                phase: SyncPhase.error,
                errorMessage: '服务端已断开，请重新搜索',
              ),
            ),
          ),
        ],
      );

      // 连接标签页：断开文案与重新搜索入口
      expect(find.text('服务端已断开，请重新搜索'), findsOneWidget);
      expect(find.text('发现服务端'), findsWidgets);

      // 同步标签页：作用域内的断开占位，而非通用未连接文案
      await tester.tap(find.text('同步').last);
      await settleTabTransition(tester);

      expect(
        find.descendant(
          of: find.byType(SyncOperationTab),
          matching: find.text('服务端已断开，请重新搜索'),
        ),
        findsOneWidget,
      );
      expect(find.text('请先在「连接」标签页中连接到服务端'), findsNothing);
    });
  });
}
