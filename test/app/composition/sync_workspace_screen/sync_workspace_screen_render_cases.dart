import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';
import 'package:oh_my_llm/features/sync/application/sync_server_controller.dart';

import '../../../features/media/helpers/fake_media_library.dart';
import '../../../helpers/async/widget_test_animation.dart';
import 'sync_workspace_screen_test_helpers.dart';

void registerSyncScreenRenderTests() {
  group('SyncScreen 媒体来源', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      RecordingMediaBrowserController.latest = null;
      RecordingMediaBrowserController.lastState = null;
      RecordingMediaBrowserController.totalInitCount = 0;
    });

    testWidgets('Android 初始媒体标签页打开远程来源并初始化浏览会话', (tester) async {
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
      await tester.pump();

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

    testWidgets('Windows 进入媒体标签页打开本地来源且不启动同步服务端', (tester) async {
      overrideWindowsPlatform();
      SharedPreferences.setMockInitialValues({
        mediaRootDirectoryStorageKey: r'D:\Media',
      });
      final preferences = await SharedPreferences.getInstance();
      final library = FakeMediaLibrary()
        ..directoryResults['/'] = [
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

      expect(factory.openedSources, [
        const LocalMediaLibrarySource(r'D:\Media'),
      ]);
      expect(library.listDirectoryCalls, ['/']);
      expect(find.text('猫.jpg'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(syncServerControllerProvider).isRunning, isFalse);
      debugDefaultTargetPlatformOverride = null;
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
    });

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

    testWidgets('媒体标签页有目录历史时系统返回只回上一级', (tester) async {
      final router = await pumpAndroidMediaTab(tester);
      RecordingMediaBrowserController.latest!.seedPathForTest(
        currentPath: '/相册/旅行',
        pathHistory: ['/相册'],
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

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
  });
}
