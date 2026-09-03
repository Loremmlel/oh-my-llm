// 本文件的语义断言依赖 testWidgets 默认启用语义（Flutter 3.44+）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_state.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/video_player_controls.dart';

import '../../../../helpers/responsive_viewport_cases.dart';
import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

NetworkMediaResource _testResource() =>
    NetworkMediaResource(Uri.parse('http://localhost/test.mp4'));

VideoPlayerPlatformBindings _mobileTestBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

VideoPlayerPlatformBindings _desktopTestBindings() =>
    DesktopVideoPlayerBindings(fullscreen: FakeVideoFullscreenController());

SemanticsFinder semanticsByTooltip(String tooltip) =>
    find.semantics.byPredicate((node) => node.tooltip == tooltip);

SemanticsFinder focusedNode() => find.semantics.byFlag(SemanticsFlag.isFocused);

class _NeverInitializingVideoPlayerController
    extends FakeVideoPlayerController {
  @override
  Future<void> initialize() => Completer<void>().future;
}

Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onDidRemovePage: (page) {},
    ),
  );
}

Future<void> _pumpVideo(
  WidgetTester tester,
  FakeVideoPlayerController fake, {
  Size? viewport,
  VideoPlayerPlatformBindings Function()? bindings,
}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    _wrapWithMaterialApp(
      VideoPlayerPage(
        resource: _testResource(),
        fileName: 'test-video.mp4',
        controllerFactory: (resource) => fake,
        platformBindingsFactory: bindings ?? _mobileTestBindings,
      ),
    ),
  );
  await fake.waitForInitializeCount(1);
  await tester.pump();
  fake.seekToCalls.clear();
  fake.setPlaybackSpeedCalls.clear();
  fake.playCallCount = 0;
  fake.pauseCallCount = 0;
}

Future<void> _tab(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
}

void main() {
  group('关键语义', () {
    for (final viewport in [phonePortrait, wideDesktop]) {
      testWidgets('${viewport.name} 下播放与控制语义可达', (tester) async {
        final fake = FakeVideoPlayerController();
        fake.fakePosition = const Duration(seconds: 30);
        await _pumpVideo(tester, fake, viewport: viewport.size);

        expect(find.semantics.byLabel('视频播放器：test-video.mp4'), findsOneWidget);
        expect(semanticsByTooltip('关闭视频'), findsOneWidget);
        expect(semanticsByTooltip('暂停'), findsOneWidget);
        expect(find.semantics.byLabel('播放进度'), findsOneWidget);
      });
    }

    testWidgets('播放表面暴露唯一按钮语义和状态', (tester) async {
      await _pumpVideo(tester, FakeVideoPlayerController());

      final surface = find.semantics.byLabel('视频播放器：test-video.mp4');
      expect(surface, findsOneWidget);
      expect(
        surface,
        isSemantics(
          value: '正在播放，播放控件已显示',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('加载态只有进度语义而没有播放表面', (tester) async {
      await tester.pumpWidget(
        _wrapWithMaterialApp(
          VideoPlayerPage(
            resource: _testResource(),
            fileName: 'test-video.mp4',
            controllerFactory: (resource) =>
                _NeverInitializingVideoPlayerController(),
            platformBindingsFactory: _mobileTestBindings,
          ),
        ),
      );
      await tester.pump();

      expect(find.semantics.byLabel('正在加载视频'), findsOneWidget);
      expect(find.semantics.byLabel('视频播放器：test-video.mp4'), findsNothing);
    });

    testWidgets('播放表面语义操作切换控制栏可达性', (tester) async {
      await _pumpVideo(tester, FakeVideoPlayerController());

      tester.semantics.tap(find.semantics.byLabel('视频播放器：test-video.mp4'));
      await tester.pump();

      expect(
        find.semantics.byLabel('视频播放器：test-video.mp4'),
        isSemantics(value: '正在播放，播放控件已隐藏'),
      );
      expect(semanticsByTooltip('关闭视频'), findsNothing);
      expect(find.semantics.byLabel('播放进度'), findsNothing);
    });
  });

  testWidgets('Space 提供播放暂停的键盘等价操作', (tester) async {
    final fake = FakeVideoPlayerController();
    await _pumpVideo(tester, fake);
    await _tab(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(fake.pauseCallCount, 1);
    expect(semanticsByTooltip('播放'), findsOneWidget);
  });

  testWidgets('错误状态是可操作的 live status', (tester) async {
    final failing = FakeVideoPlayerController(
      initializeError: Exception('network error'),
    );
    await tester.pumpWidget(
      _wrapWithMaterialApp(
        VideoPlayerPage(
          resource: _testResource(),
          fileName: 'test-video.mp4',
          controllerFactory: (resource) => failing,
          platformBindingsFactory: _mobileTestBindings,
        ),
      ),
    );
    await failing.waitForInitializeCount(1);
    await tester.pump();

    expect(
      find.semantics.byPredicate(
        (node) =>
            node.flagsCollection.isLiveRegion && node.label.contains('视频加载失败'),
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == '重试' &&
            node.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
      findsOneWidget,
    );
  });

  testWidgets('快进反馈只产生一个 live region', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 30);
    await _pumpVideo(tester, fake);
    await _tab(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final status = find.semantics.byLabel('已快进 15 秒');
    expect(status, findsOneWidget);
    expect(status, isSemantics(isLiveRegion: true));
    expect(find.semantics.byValue('15s'), findsNothing);
  });

  testWidgets('音量反馈只产生一个实际百分比 live region', (tester) async {
    await tester.pumpWidget(
      _wrapWithMaterialApp(
        const VideoCenterHint(
          visible: true,
          feedback: VideoVolumeFeedback(volume: 0.55, isMuted: false),
          showPauseIcon: false,
        ),
      ),
    );

    final status = find.semantics.byLabel('音量 55%');
    expect(status, findsOneWidget);
    expect(status, isSemantics(isLiveRegion: true));
    expect(
      find.semantics.byPredicate((node) => node.flagsCollection.isLiveRegion),
      findsOneWidget,
    );
  });

  group('进度语义', () {
    testWidgets('有时长时进度可增减且显示实际时间', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30);
      await _pumpVideo(tester, fake);

      expect(
        find.semantics.byLabel('播放进度'),
        isSemantics(
          value: '00:30 / 05:00',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
    });

    testWidgets('无时长时进度禁用且不可增减', (tester) async {
      final fake = FakeVideoPlayerController()..fakeDuration = Duration.zero;
      await _pumpVideo(tester, fake);

      expect(
        find.semantics.byLabel('播放进度'),
        isSemantics(
          hasEnabledState: true,
          isEnabled: false,
          hasIncreaseAction: false,
          hasDecreaseAction: false,
        ),
      );
    });
  });

  testWidgets('Tab 从播放表面进入关闭按钮', (tester) async {
    await _pumpVideo(tester, FakeVideoPlayerController());

    await _tab(tester);
    expect(focusedNode(), isSemantics(label: '视频播放器：test-video.mp4'));
    await _tab(tester);
    expect(focusedNode(), isSemantics(tooltip: '关闭视频'));
  });

  testWidgets('Windows 表面提供桌面交互帮助文本', (tester) async {
    await _pumpVideo(
      tester,
      FakeVideoPlayerController(),
      bindings: _desktopTestBindings,
    );

    expect(
      find.semantics.byLabel('视频播放器：test-video.mp4'),
      isSemantics(
        hint: '激活以播放或暂停；双击或 F 切换全屏，左右方向键快退或快进 5 秒，右方向键长按临时 3 倍速，上下方向键调整音量，M 静音，Escape 退出全屏或关闭',
      ),
    );
  });

  testWidgets('全屏失败反馈作为 live region 可达', (tester) async {
    final fullscreen = FakeVideoFullscreenController()..failNext = true;
    await _pumpVideo(
      tester,
      FakeVideoPlayerController(),
      bindings: () => DesktopVideoPlayerBindings(fullscreen: fullscreen),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    final status = find.semantics.byLabel('无法切换全屏');
    expect(status, findsOneWidget);
    expect(status, isSemantics(isLiveRegion: true));
  });
}
