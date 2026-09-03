import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import '../../../helpers/async/widget_test_animation.dart';
import '../../../features/media/helpers/fake_media_library.dart';
import 'sync_workspace_screen_test_helpers.dart';

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void registerSyncScreenResponsiveTests() {
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

  testWidgets('390x844 Android 竖屏: 活动媒体会话只显示密度菜单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final preferences = await _freshPrefs();
    final factory = FakeMediaLibraryFactory(FakeMediaLibrary());
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: phonePortrait.size,
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

    // 紧凑壳层：只渲染「显示密度」菜单，不渲染三个展开 tooltip。
    expect(find.byTooltip('显示密度'), findsOneWidget);
    expect(find.byTooltip('紧凑密度'), findsNothing);
    expect(find.byTooltip('标准密度'), findsNothing);
    expect(find.byTooltip('舒适密度'), findsNothing);
    expect(tester.takeException(), isNull);
    // 测试框架在 test body 末尾校验 foundation debug 变量已复位（addTearDown 在
    // 该校验之后才执行），故 body 内显式复位，addTearDown 仅作失败路径兜底。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('960x640 Windows: 活动媒体会话显示三个展开密度 tooltip', (tester) async {
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
      extraOverrides: [
        mediaLibraryFactoryProvider.overrideWithValue(factory),
        mediaBrowserControllerProvider.overrideWith(
          RecordingMediaBrowserController.new,
        ),
      ],
    );

    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('媒体')),
    );
    await settleTabTransition(tester);

    // 宽壳层：渲染三个展开密度 tooltip，不渲染「显示密度」菜单。
    expect(find.byTooltip('紧凑密度'), findsOneWidget);
    expect(find.byTooltip('标准密度'), findsOneWidget);
    expect(find.byTooltip('舒适密度'), findsOneWidget);
    expect(find.byTooltip('显示密度'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
