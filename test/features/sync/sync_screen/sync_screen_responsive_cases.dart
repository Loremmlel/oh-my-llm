import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import '../../../helpers/widget_test_animation.dart';
import 'sync_screen_test_helpers.dart';

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void registerSyncScreenResponsiveTests() {
  for (final width in [390.0, 600.0]) {
    testWidgets('${width.toInt()}px: 同步页关键内容可达', (tester) async {
      final preferences = await _freshPrefs();
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        size: Size(width, 1200),
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
  }

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

  testWidgets('844x390 Android 横屏: 媒体 tab 可达且离开后 reset', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final preferences = await _freshPrefs();
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: androidLandscape,
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

    expect(find.byType(MediaBrowserTab), findsOneWidget);
    expect(RecordingMediaBrowserController.lastState!.server, isNotNull);
    // 路径栏根 chip 在低高度横屏下仍可见，证明媒体内容区可达。
    expect(find.text('🏠'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 离开媒体 tab：session reset 契约保持。
    await tester.tap(find.text('连接'));
    await settleTabTransition(tester);
    expect(RecordingMediaBrowserController.lastState, MediaBrowserState());
    expect(tester.takeException(), isNull);
    // 测试框架在 test body 末尾校验 foundation debug 变量已复位（addTearDown 在
    // 该校验之后才执行），故 body 内显式复位，addTearDown 仅作失败路径兜底。
    debugDefaultTargetPlatformOverride = null;
  });
}
