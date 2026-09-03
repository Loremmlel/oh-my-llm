import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

const _rightHoldThreshold = Duration(milliseconds: 400);

NetworkMediaResource _testResource() =>
    NetworkMediaResource(Uri.parse('http://localhost/test.mp4'));

class DesktopVideoTestHarness {
  DesktopVideoTestHarness({
    required this.fake,
    required this.fullscreen,
    required this.tester,
  });

  final FakeVideoPlayerController fake;
  final FakeVideoFullscreenController fullscreen;
  final WidgetTester tester;

  FocusNode get surfaceFocusNode {
    final focus = tester.widget<Focus>(
      find
          .ancestor(of: find.byType(VideoPlayer), matching: find.byType(Focus))
          .first,
    );
    return focus.focusNode!;
  }

  Finder get videoSurface => find.byType(VideoPlayer);

  Offset get videoSurfaceCenter => tester.getCenter(videoSurface);
}

Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onDidRemovePage: (page) {},
    ),
  );
}

Future<DesktopVideoTestHarness> pumpDesktopVideo(
  WidgetTester tester, {
  Duration position = const Duration(seconds: 30),
  double volume = 1.0,
}) async {
  final fake = FakeVideoPlayerController()
    ..fakePosition = position
    ..fakeVolume = volume;
  final fullscreen = FakeVideoFullscreenController();
  await tester.pumpWidget(
    _wrapWithMaterialApp(
      VideoPlayerPage(
        resource: _testResource(),
        fileName: 'test-video.mp4',
        controllerFactory: (resource) => fake,
        platformBindingsFactory: () =>
            DesktopVideoPlayerBindings(fullscreen: fullscreen),
      ),
    ),
  );
  await fake.waitForInitializeCount(1);
  await tester.pump();
  fake.seekToCalls.clear();
  fake.setVolumeCalls.clear();
  fake.setPlaybackSpeedCalls.clear();
  return DesktopVideoTestHarness(
    fake: fake,
    fullscreen: fullscreen,
    tester: tester,
  );
}

Future<DesktopVideoTestHarness> pumpPushedDesktopVideo(
  WidgetTester tester, {
  bool fullscreen = false,
}) async {
  final fake = FakeVideoPlayerController()
    ..fakePosition = const Duration(seconds: 30);
  final fullscreenController = FakeVideoFullscreenController()
    ..actual = fullscreen
    ..desired = fullscreen;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => VideoPlayerPage(
                resource: _testResource(),
                fileName: 'test-video.mp4',
                controllerFactory: (resource) => fake,
                platformBindingsFactory: () => DesktopVideoPlayerBindings(
                  fullscreen: fullscreenController,
                ),
              ),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          ),
          child: const Text('打开播放器'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开播放器'));
  await tester.pump();
  await fake.waitForInitializeCount(1);
  await tester.pump();
  fake.seekToCalls.clear();
  return DesktopVideoTestHarness(
    fake: fake,
    fullscreen: fullscreenController,
    tester: tester,
  );
}

void main() {
  testWidgets('初始化成功后播放表面自动获得主焦点', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    expect(harness.surfaceFocusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('初始化期间打开的弹层优先消费 Escape', (tester) async {
    final gate = Completer<void>();
    final fake = FakeVideoPlayerController()..initializeGate = gate;
    final fullscreen = FakeVideoFullscreenController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => VideoPlayerPage(
                  resource: _testResource(),
                  fileName: 'test-video.mp4',
                  controllerFactory: (resource) => fake,
                  platformBindingsFactory: () =>
                      DesktopVideoPlayerBindings(fullscreen: fullscreen),
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            ),
            child: const Text('打开播放器'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开播放器'));
    await tester.pump();
    await fake.waitForInitializeCount(1);
    await tester.tap(find.byTooltip('播放速度，当前 1.0 倍'));
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(VideoPlayerPage), findsOneWidget);
    expect(find.text('0.5x'), findsNothing);
  });

  testWidgets('左右方向键转发五秒 Seek', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(harness.fake.seekToCalls, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(harness.fake.seekToCalls.last, const Duration(seconds: 35));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    expect(harness.fake.seekToCalls.last, const Duration(seconds: 30));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
  });

  testWidgets('M 与上下方向键转发静音和音量命令', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(harness.fake.setVolumeCalls.last, 0.0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(harness.fake.setVolumeCalls.last, closeTo(0.95, 0.0001));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });

  testWidgets('F 转发原生全屏切换', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(harness.fullscreen.calls, contains('toggle'));
    expect(harness.fullscreen.actualFullscreen, isTrue);
  });

  testWidgets('全屏 Escape 先退出全屏再关闭页面', (tester) async {
    final harness = await pumpPushedDesktopVideo(tester, fullscreen: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(harness.fullscreen.calls, contains('exitIfFullscreen'));
    expect(find.text('打开播放器'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('打开播放器'), findsOneWidget);
  });

  testWidgets('全屏 generic Back 恢复窗口并关闭页面', (tester) async {
    final harness = await pumpPushedDesktopVideo(tester, fullscreen: true);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump();
    expect(harness.fullscreen.calls, contains('restoreAndDispose'));
    expect(find.text('打开播放器'), findsOneWidget);
    expect(harness.fake.disposeCount, 1);
  });

  testWidgets('音量弹层消费 Escape 并恢复播放表面焦点', (tester) async {
    final harness = await pumpPushedDesktopVideo(tester);
    await tester.tap(find.byTooltip('音量，当前 100%'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoPlayerPage), findsOneWidget);
    expect(harness.surfaceFocusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('触摸双击在桌面只切换全屏', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    await tester.tapAt(
      harness.videoSurfaceCenter,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(
      harness.videoSurfaceCenter,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(harness.fullscreen.toggleCallCount, 1);
    expect(harness.fake.pauseCallCount, 0);
    expect(harness.fake.seekToCalls, isEmpty);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('播放区域垂直滚轮转发音量命令', (tester) async {
    final harness = await pumpDesktopVideo(tester, volume: 0.5);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: harness.videoSurfaceCenter,
        scrollDelta: const Offset(0, -1),
      ),
    );
    await tester.pump();
    expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
  });

  testWidgets('应用失焦释放右键临时倍速且不补 Seek', (tester) async {
    final harness = await pumpDesktopVideo(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(_rightHoldThreshold);
    expect(harness.fake.setPlaybackSpeedCalls, [3.0]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

    expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
    expect(harness.fake.seekToCalls, isEmpty);
  });
}
