import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';
import 'package:oh_my_llm/features/sync/domain/models/discovery/discovered_server.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_protocol_version.dart';
import 'package:oh_my_llm/features/sync/domain/models/protocol/sync_types.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/sync_operation_tab.dart';

import '../../../helpers/async/widget_test_animation.dart';
import '../../../features/media/helpers/fake_media_library.dart';
import 'sync_workspace_screen_test_helpers.dart';

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
      final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        bindMediaLibraryFactory: false,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(connectedSyncState()),
          ),
          mediaLibraryFactoryProvider.overrideWithValue(factory),
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
      // 激活远端会话：工厂记录到 RemoteMediaLibrarySource，浏览器从根目录加载
      expect(
        factory.openedSources,
        contains(
          RemoteMediaLibrarySource(
            Uri(scheme: 'http', host: '192.168.1.5', port: 8080),
          ),
        ),
      );
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
      final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        bindMediaLibraryFactory: false,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(connectedSyncState()),
          ),
          mediaLibraryFactoryProvider.overrideWithValue(factory),
          mediaBrowserControllerProvider.overrideWith(
            RecordingMediaBrowserController.new,
          ),
        ],
      );
      // post-frame 回调触发激活链，补一帧让异步微任务落定
      await tester.pump();

      expect(find.text('媒体'), findsAtLeast(1));
      expect(
        factory.openedSources,
        contains(
          RemoteMediaLibrarySource(
            Uri(scheme: 'http', host: '192.168.1.5', port: 8080),
          ),
        ),
      );
      expect(RecordingMediaBrowserController.totalInitCount, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'Windows shows media tab and missing root returns to Connection',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        await pumpSyncScreen(tester, preferences: preferences);

        await tester.tap(
          find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
        );
        await settleTabTransition(tester);
        expect(find.text('尚未配置媒体根目录'), findsOneWidget);
        expect(find.text('返回连接'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('Windows 进入媒体 Tab 打开本地来源、加载根目录且不启动服务端', (tester) async {
      overrideWindowsPlatform();
      SharedPreferences.setMockInitialValues({
        mediaRootDirectoryStorageKey: r'D:\Media',
      });
      final preferences = await SharedPreferences.getInstance();
      final library = FakeMediaLibrary()
        ..directoryResults['/'] = [
          // 不带缩略图信号：tile 走静态回退图标，避免缩略图 FutureProvider
          // 的「已解析 null」分支渲染永不结束的细进度条（该分支生产不可达）
          const FileItem(
            name: '猫.jpg',
            isDirectory: false,
            sizeBytes: 1,
            relativePath: '/猫.jpg',
          ),
        ];
      final factory = FakeMediaLibraryFactory(library);
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        bindMediaLibraryFactory: false,
        extraOverrides: [
          mediaLibraryFactoryProvider.overrideWithValue(factory),
        ],
      );

      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
      );
      await settleTabTransition(tester);

      // 激活本地来源：只打开配置的根目录，无任何远端来源
      expect(factory.openedSources, [
        const LocalMediaLibrarySource(r'D:\Media'),
      ]);
      // 浏览器从本地库加载根目录；未连接 Sync 服务端也无需启动同步服务
      expect(library.listDirectoryCalls, ['/']);
      expect(find.text('猫.jpg'), findsOneWidget);
      // 会话 Active 后 AppBar 随机播放入口可见
      expect(find.byIcon(Icons.shuffle), findsOneWidget);
      // ProviderScope 的继承 scope 在树中位于 ProviderScope 之下，取子级
      // context 才能解析容器；同步服务端不应因进入媒体 Tab 而启动。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(syncServerControllerProvider).isRunning, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Windows 离开媒体 Tab 失效会话并重置；活动期间修改根目录不影响来源，重新进入后生效', (
      tester,
    ) async {
      overrideWindowsPlatform();
      SharedPreferences.setMockInitialValues({
        mediaRootDirectoryStorageKey: r'D:\Media',
      });
      final preferences = await SharedPreferences.getInstance();
      final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        bindMediaLibraryFactory: false,
        extraOverrides: [
          mediaLibraryFactoryProvider.overrideWithValue(factory),
          mediaBrowserControllerProvider.overrideWith(
            RecordingMediaBrowserController.new,
          ),
          shufflePlaybackControllerProvider.overrideWith(
            RecordingShufflePlaybackController.new,
          ),
        ],
      );
      // ProviderScope 的继承 scope 在树中位于 ProviderScope 之下，取子级
      // context 才能解析容器；后续用它驱动根目录配置并观察会话状态。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
      );
      await settleTabTransition(tester);
      expect(factory.openedSources, [
        const LocalMediaLibrarySource(r'D:\Media'),
      ]);
      expect(RecordingMediaBrowserController.totalInitCount, 1);

      // 会话活动期间修改根目录配置：活动来源保持不变
      await container
          .read(mediaRootDirectoryProvider.notifier)
          .setDirectory(r'E:\NewRoot');
      expect(factory.openedSources, [
        const LocalMediaLibrarySource(r'D:\Media'),
      ]);

      // 离开媒体 Tab：会话失效，浏览器与随机播放重置
      await tester.tap(find.text('连接'));
      await settleTabTransition(tester);
      expect(
        container.read(mediaLibrarySessionProvider),
        isA<MediaLibrarySessionInactive>(),
      );
      expect(RecordingMediaBrowserController.lastState, MediaBrowserState());
      expect(
        RecordingShufflePlaybackController.lastState,
        const ShufflePlaybackIdle(),
      );

      // 重新进入：以新根目录创建全新会话并再次加载根目录
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
      );
      await settleTabTransition(tester);
      expect(factory.openedSources, [
        const LocalMediaLibrarySource(r'D:\Media'),
        const LocalMediaLibrarySource(r'E:\NewRoot'),
      ]);
      expect(RecordingMediaBrowserController.totalInitCount, 2);
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

  group('SyncScreen 媒体目录返回', () {
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

    /// Android + 已连接服务端 + 记录型浏览器控制器，进入媒体 Tab 后返回路由器。
    ///
    /// 媒体返回的所有权在 SyncWorkspaceScreen，必须让页面位于 /sync 顶层
    /// 路由内才能断言返回被消费后路由是否变化。
    Future<GoRouter> pumpAndroidMediaTab(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final router = syncWorkspaceTestRouter();
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        bindMediaLibraryFactory: false,
        router: router,
        extraOverrides: [
          syncClientControllerProvider.overrideWith(
            () => SeededSyncClientController(connectedSyncState()),
          ),
          mediaLibraryFactoryProvider.overrideWithValue(
            FakeMediaLibraryFactory(FakeMediaLibrary()),
          ),
          mediaBrowserControllerProvider.overrideWith(
            RecordingMediaBrowserController.new,
          ),
        ],
      );
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
      );
      await settleTabTransition(tester);
      return router;
    }

    testWidgets('媒体 Tab 有目录历史时系统返回只回上一级目录', (tester) async {
      final router = await pumpAndroidMediaTab(tester);
      RecordingMediaBrowserController.latest!.seedPathForTest(
        currentPath: '/相册/旅行',
        pathHistory: ['/相册'],
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

      // 返回只消费一次目录回溯：路径回到 /相册，Tab 仍是媒体，路由不变
      expect(RecordingMediaBrowserController.latest!.goBackCount, 1);
      expect(RecordingMediaBrowserController.latest!.state.currentPath, '/相册');
      expect(
        RecordingMediaBrowserController.latest!.state.pathHistory,
        isEmpty,
      );
      expect(router.routeInformationProvider.value.uri.path, '/sync');
      expect(find.text('作为客户端'), findsNothing);
      expect(find.text('相册'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('媒体根目录时系统返回切回连接 Tab 且留在 /sync', (tester) async {
      final router = await pumpAndroidMediaTab(tester);
      RecordingMediaBrowserController.latest!.seedPathForTest(
        currentPath: '/',
        pathHistory: [],
      );

      await tester.binding.handlePopRoute();
      await settleTabTransition(tester);

      // 根目录没有可退目录：不调用 goBack，直接切回「连接」Tab，路由保持
      expect(RecordingMediaBrowserController.latest!.goBackCount, 0);
      expect(router.routeInformationProvider.value.uri.path, '/sync');
      expect(find.text('作为客户端'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('切回连接 Tab 后系统返回不回溯媒体目录而退回对话页', (tester) async {
      final router = await pumpAndroidMediaTab(tester);
      RecordingMediaBrowserController.latest!.seedPathForTest(
        currentPath: '/相册/旅行',
        pathHistory: ['/相册'],
      );
      await tester.tap(find.text('连接'));
      await settleTabTransition(tester);

      await tester.binding.handlePopRoute();
      await settleRouteTransition(tester);

      // 媒体 Tab 已离屏：返回权交回 AppShell，退回对话页且不再触碰目录
      expect(RecordingMediaBrowserController.latest!.goBackCount, 0);
      expect(router.routeInformationProvider.value.uri.path, '/chat');
      expect(find.text('对话页'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
