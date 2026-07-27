import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/sync_types.dart';

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

    testWidgets('渲染标题、标签页和连接模式选择器', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      expect(find.text('局域网同步'), findsOneWidget);
      expect(find.text('连接'), findsAtLeast(1));
      expect(find.text('同步'), findsAtLeast(1));
      expect(find.text('作为客户端'), findsOneWidget);
      expect(find.text('作为服务端'), findsOneWidget);
    });

    testWidgets('默认显示连接标签页', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(RecordingMediaBrowserController.lastState!.server, isNotNull);
      expect(RecordingMediaBrowserController.totalInitCount, 1);
      RecordingShufflePlaybackController.latest!.activateForTest();

      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(RecordingMediaBrowserController.lastState, MediaBrowserState());
      expect(
        RecordingShufflePlaybackController.lastState,
        const ShufflePlaybackIdle(),
      );

      await tester.tap(find.text('媒体'));
      await tester.pumpAndSettle();
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
  });
}
