import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/desktop_video_interaction_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_state.dart';

import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

const _rightHoldThreshold = Duration(milliseconds: 400);
const _rightHoldThresholdBefore = Duration(milliseconds: 399);
const _wheelThrottleWindow = Duration(milliseconds: 50);

class FakeTimers {
  FakeTimers(this._tester);

  final WidgetTester _tester;

  Future<void> elapse(Duration duration) => _tester.pump(duration);
}

class DesktopHarness {
  DesktopHarness({
    required this.playback,
    required this.fake,
    required this.fullscreen,
    required this.desktop,
    required this.timers,
    required this.closeRequests,
  });

  final VideoPlaybackController playback;
  final FakeVideoPlayerController fake;
  final FakeVideoFullscreenController fullscreen;
  final DesktopVideoInteractionController desktop;
  final FakeTimers timers;
  final RequestCloseSpy closeRequests;

  DesktopVideoInteractionController get controller => desktop;

  int get closeRequestCount => closeRequests.count;

  KeyEventResult keyDown(LogicalKeyboardKey key) =>
      desktop.handleSurfaceKey(_keyEvent(key, down: true));

  KeyEventResult keyUp(LogicalKeyboardKey key) =>
      desktop.handleSurfaceKey(_keyEvent(key, down: false));

  KeyEventResult repeat(LogicalKeyboardKey key) =>
      desktop.handleSurfaceKey(_keyRepeat(key));

  KeyEventResult pageKeyDown(LogicalKeyboardKey key) =>
      desktop.handlePageKey(_keyEvent(key, down: true));

  KeyEventResult pageKeyUp(LogicalKeyboardKey key) =>
      desktop.handlePageKey(_keyEvent(key, down: false));

  KeyEventResult pageKeyRepeat(LogicalKeyboardKey key) =>
      desktop.handlePageKey(_keyRepeat(key));
}

class RequestCloseSpy {
  int count = 0;
}

Future<DesktopHarness> createDesktopHarness({
  required WidgetTester tester,
  FakeVideoPlayerController? fake,
  FakeVideoFullscreenController? fullscreen,
  bool isPlaying = true,
}) async {
  final player =
      fake ??
      (FakeVideoPlayerController()..fakePosition = const Duration(seconds: 30));
  final playback = VideoPlaybackController(
    resource: NetworkMediaResource(Uri.parse('http://localhost/test.mp4')),
    controllerFactory: (resource) => player,
    onStateChanged: () {},
  );
  final fullscreenController = fullscreen ?? FakeVideoFullscreenController();
  final closeRequests = RequestCloseSpy();
  final desktop = DesktopVideoInteractionController(
    playback: playback,
    fullscreen: fullscreenController,
    onRequestClose: () async => closeRequests.count++,
    onInteractionChanged: () {},
  );
  await playback.initialize();
  if (!isPlaying) {
    playback.togglePlayPause();
  }
  player.setPlaybackSpeedCalls.clear();
  player.seekToCalls.clear();
  player.setVolumeCalls.clear();
  player.playCallCount = 0;
  player.pauseCallCount = 0;
  return DesktopHarness(
    playback: playback,
    fake: player,
    fullscreen: fullscreenController,
    desktop: desktop,
    timers: FakeTimers(tester),
    closeRequests: closeRequests,
  );
}

KeyEvent _keyEvent(LogicalKeyboardKey key, {required bool down}) {
  final physical = _physicalKeyFor(key);
  if (down) {
    return KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
  }
  return KeyUpEvent(
    physicalKey: physical,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

KeyRepeatEvent _keyRepeat(LogicalKeyboardKey key) => KeyRepeatEvent(
  physicalKey: _physicalKeyFor(key),
  logicalKey: key,
  timeStamp: Duration.zero,
);

PhysicalKeyboardKey _physicalKeyFor(LogicalKeyboardKey key) {
  for (final physical in PhysicalKeyboardKey.knownPhysicalKeys) {
    if (physical.debugName == key.debugName) return physical;
  }
  return PhysicalKeyboardKey(0);
}

void _dispose(DesktopHarness harness) {
  harness.desktop.dispose();
  harness.playback.dispose();
}

void main() {
  testWidgets('右方向键阈值前松开只快进五秒', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.keyDown(LogicalKeyboardKey.arrowRight);
    await tester.pump(_rightHoldThresholdBefore);
    harness.keyUp(LogicalKeyboardKey.arrowRight);

    expect(harness.fake.seekToCalls, [const Duration(seconds: 35)]);
    expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
    _dispose(harness);
  });

  testWidgets('右方向键达到阈值临时三倍速且松开恢复', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.keyDown(LogicalKeyboardKey.arrowRight);
    await tester.pump(_rightHoldThreshold);

    expect(harness.fake.seekToCalls, isEmpty);
    expect(harness.fake.setPlaybackSpeedCalls, [3.0]);
    harness.keyUp(LogicalKeyboardKey.arrowRight);
    expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
    _dispose(harness);
  });

  testWidgets('暂停时右方向键长按不加速也不补 Seek', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.playback.togglePlayPause();
    harness.keyDown(LogicalKeyboardKey.arrowRight);
    await tester.pump(_rightHoldThreshold);
    harness.keyUp(LogicalKeyboardKey.arrowRight);

    expect(harness.fake.seekToCalls, isEmpty);
    expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
    _dispose(harness);
  });

  testWidgets('窗口失焦释放临时倍速并忽略迟到 KeyUp', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.keyDown(LogicalKeyboardKey.arrowRight);
    await tester.pump(_rightHoldThreshold);

    harness.desktop.onWindowBlur();
    harness.keyUp(LogicalKeyboardKey.arrowRight);

    expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
    expect(harness.fake.seekToCalls, isEmpty);
    _dispose(harness);
  });

  testWidgets('左方向键只在 KeyDown 快退一次', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.keyDown(LogicalKeyboardKey.arrowLeft);
    harness.repeat(LogicalKeyboardKey.arrowLeft);
    harness.keyUp(LogicalKeyboardKey.arrowLeft);

    expect(harness.fake.seekToCalls, [const Duration(seconds: 25)]);
    _dispose(harness);
  });

  testWidgets('上下方向键及 repeat 每次调整百分之五音量', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 30)
      ..fakeVolume = 0.5;
    final harness = await createDesktopHarness(tester: tester, fake: fake);
    addTearDown(harness.desktop.dispose);

    harness.keyDown(LogicalKeyboardKey.arrowUp);
    harness.repeat(LogicalKeyboardKey.arrowUp);
    harness.keyDown(LogicalKeyboardKey.arrowDown);

    expect(harness.fake.setVolumeCalls, hasLength(3));
    expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
    _dispose(harness);
  });

  testWidgets('Space 与媒体键只在 KeyDown 切换播放状态', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    harness.keyDown(LogicalKeyboardKey.space);
    harness.keyDown(LogicalKeyboardKey.mediaPlayPause);
    harness.repeat(LogicalKeyboardKey.space);
    harness.keyUp(LogicalKeyboardKey.space);

    expect(harness.fake.pauseCallCount, 1);
    expect(harness.fake.playCallCount, 1);
    _dispose(harness);
  });

  testWidgets('M 调用共享静音命令', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    harness.pageKeyDown(LogicalKeyboardKey.keyM);

    expect(harness.playback.state.isMuted, isTrue);
    expect(harness.fake.setVolumeCalls.last, 0.0);
    _dispose(harness);
  });

  testWidgets('F 切换原生全屏并同步状态', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    harness.pageKeyDown(LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(harness.fullscreen.calls, ['toggle']);
    expect(harness.fullscreen.actual, isTrue);
    _dispose(harness);
  });

  testWidgets('全屏切换失败显示反馈且不伪造状态', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.fullscreen.failNext = true;

    harness.pageKeyDown(LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(harness.fullscreen.actual, isFalse);
    expect(
      harness.playback.state.centerFeedback,
      isA<VideoOperationFailureFeedback>(),
    );
    _dispose(harness);
  });

  testWidgets('全屏时 Escape 只退出全屏', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.pageKeyDown(LogicalKeyboardKey.keyF);
    await tester.pump();

    harness.pageKeyDown(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(harness.fullscreen.calls, ['toggle', 'exitIfFullscreen']);
    expect(harness.closeRequestCount, 0);
    _dispose(harness);
  });

  testWidgets('窗口模式 Escape 只请求关闭一次', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    harness.pageKeyDown(LogicalKeyboardKey.escape);
    harness.pageKeyRepeat(LogicalKeyboardKey.escape);
    harness.pageKeyUp(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(harness.closeRequestCount, 1);
    _dispose(harness);
  });

  testWidgets('播放中静止三秒后同时隐藏控件与光标', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.controller.onPointerActivity();

    await harness.timers.elapse(const Duration(seconds: 3));

    expect(harness.playback.state.controlsVisible, isFalse);
    expect(harness.controller.isCursorVisible, isFalse);
    _dispose(harness);
  });

  testWidgets('控制栏悬停或聚焦阻止自动隐藏', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.controller.onControlsPointerEnter();
    harness.controller.onControlsFocusChanged(true);

    await harness.timers.elapse(const Duration(seconds: 3));

    expect(harness.playback.state.controlsVisible, isTrue);
    expect(harness.controller.isCursorVisible, isTrue);
    _dispose(harness);
  });

  testWidgets('暂停状态不启动自动隐藏', (tester) async {
    final harness = await createDesktopHarness(
      tester: tester,
      isPlaying: false,
    );
    addTearDown(harness.desktop.dispose);
    harness.controller.onPointerActivity();

    await harness.timers.elapse(const Duration(seconds: 3));

    expect(harness.playback.state.controlsVisible, isTrue);
    expect(harness.controller.isCursorVisible, isTrue);
    _dispose(harness);
  });

  testWidgets('窗口失焦取消光标计时并恢复可见', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);
    harness.controller.onPointerActivity();
    await harness.timers.elapse(const Duration(seconds: 1));

    harness.controller.onWindowBlur();
    await harness.timers.elapse(const Duration(seconds: 3));

    expect(harness.controller.isCursorVisible, isTrue);
    _dispose(harness);
  });

  testWidgets('垂直滚轮调整音量并显示实际反馈', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 30)
      ..fakeVolume = 0.5;
    final harness = await createDesktopHarness(tester: tester, fake: fake);
    addTearDown(harness.desktop.dispose);

    harness.controller.handlePointerSignal(
      PointerScrollEvent(scrollDelta: const Offset(0, -1)),
    );

    expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
    expect(harness.playback.state.centerFeedback, isA<VideoVolumeFeedback>());
    _dispose(harness);
  });

  testWidgets('水平滚轮不改变音量', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    harness.controller.handlePointerSignal(
      PointerScrollEvent(scrollDelta: const Offset(2, 1)),
    );

    expect(harness.fake.setVolumeCalls, isEmpty);
    _dispose(harness);
  });

  testWidgets('滚轮音量使用五十毫秒 leading-edge 节流', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 30)
      ..fakeVolume = 0.5;
    final harness = await createDesktopHarness(tester: tester, fake: fake);
    addTearDown(harness.desktop.dispose);
    const event = PointerScrollEvent(scrollDelta: Offset(0, -1));

    harness.controller.handlePointerSignal(event);
    harness.controller.handlePointerSignal(event);
    expect(harness.fake.setVolumeCalls, hasLength(1));

    await harness.timers.elapse(_wheelThrottleWindow);
    harness.controller.handlePointerSignal(event);
    expect(harness.fake.setVolumeCalls, hasLength(2));
    _dispose(harness);
  });

  testWidgets('页面销毁后忽略迟到的全屏退出结果', (tester) async {
    final fullscreen = FakeVideoFullscreenController();
    final exitGate = Completer<VideoFullscreenCommandResult>();
    fullscreen.exitGate = exitGate;
    final harness = await createDesktopHarness(
      tester: tester,
      fullscreen: fullscreen,
    );

    harness.pageKeyDown(LogicalKeyboardKey.escape);
    harness.desktop.dispose();
    exitGate.complete(
      const VideoFullscreenCommandResult(consumed: true, succeeded: false),
    );
    await tester.pump();

    expect(harness.playback.state.centerFeedback, isNull);
    expect(harness.closeRequestCount, 0);
    harness.playback.dispose();
  });
}
