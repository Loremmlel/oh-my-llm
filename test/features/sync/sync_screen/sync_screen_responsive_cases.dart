import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import '../../../helpers/widget_test_animation.dart';
import '../../media/helpers/fake_media_library.dart';
import 'sync_screen_test_helpers.dart';

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void registerSyncScreenResponsiveTests() {
  testWidgets('390px: 同步页关键内容可达', (tester) async {
    final preferences = await _freshPrefs();
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: const Size(390, 1200),
    );

    expect(find.text('局域网同步'), findsOneWidget);
    expect(find.text('连接'), findsWidgets);
    expect(find.text('同步'), findsWidgets);
    expect(find.text('作为客户端'), findsOneWidget);
    expect(find.text('作为服务端'), findsOneWidget);

    // 紧凑宽度下 NavigationBar 底部导航同样渲染「同步」destination label，
    // 且位于 body 之后，find.text('同步').last 会命中该 label（点击为空操作）。
    // 用 TabBar 作用域精确定位内部 tab。
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('同步')),
    );
    await settleTabTransition(tester);
    expect(find.text('请先在「连接」标签页中连接到服务端'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [
    shellBelowBoundary,
    shellAtBoundary,
    shellAboveBoundary,
  ]) {
    testWidgets('${viewport.name}: 同步页壳层边界', (tester) async {
      final preferences = await _freshPrefs();
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        size: viewport.size,
      );

      expect(find.text('局域网同步'), findsOneWidget);
      if (viewport.shellMode == ShellNavigationMode.bottomBar) {
        expect(find.byType(NavigationBar), findsOneWidget);
      } else {
        expect(find.byType(NavigationRail), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('844x390 Android 横屏: 低高度下媒体 tab 可达且无异常', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final preferences = await _freshPrefs();
    final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: androidLandscape,
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

    await tester.tap(find.text('媒体'));
    await settleTabTransition(tester);

    expect(find.byType(MediaBrowserTab), findsOneWidget);
    // 激活远端会话：工厂记录到 RemoteMediaLibrarySource
    expect(
      factory.openedSources,
      contains(
        RemoteMediaLibrarySource(
          Uri(scheme: 'http', host: '192.168.1.5', port: 8080),
        ),
      ),
    );
    // 路径栏根 chip 在低高度横屏下仍可见，证明媒体内容区可达。
    expect(find.text('🏠'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 测试框架在 test body 末尾校验 foundation debug 变量已复位（addTearDown 在
    // 该校验之后才执行），故 body 内显式复位，addTearDown 仅作失败路径兜底。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('960x640 Windows 窗口: 媒体 tab 可达且无异常', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      mediaRootDirectoryStorageKey: r'D:\Media',
    });
    final preferences = await SharedPreferences.getInstance();
    final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: const Size(960, 640),
      bindMediaLibraryFactory: false,
      extraOverrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );

    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
    );
    await settleTabTransition(tester);

    expect(find.byType(MediaBrowserTab), findsOneWidget);
    // 激活本地来源：工厂记录到 LocalMediaLibrarySource
    expect(factory.openedSources, [const LocalMediaLibrarySource(r'D:\Media')]);
    // 路径栏根 chip 在受限窗口下仍可见，证明媒体内容区可达。
    expect(find.text('🏠'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 与 Android 横屏用例相同：body 末尾显式复位，addTearDown 仅作失败路径兜底。
    debugDefaultTargetPlatformOverride = null;
  });
}
