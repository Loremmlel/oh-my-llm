import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/desktop_video_interaction_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_state.dart';

import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

/// 右方向键长按分类阈值（与生产 400ms 契约一致）。
const _rightHoldThreshold = Duration(milliseconds: 400);

/// 阈值前一毫秒：断言「未达阈值不分类为长按」。
const _rightHoldThresholdBefore = Duration(milliseconds: 399);

/// 滚轮 50ms leading-edge 节流窗口（与生产契约一致）。
const _wheelThrottleWindow = Duration(milliseconds: 50);

/// 假时钟：把 testWidgets 的 fake-async 时钟暴露为 [elapse]，
/// 同时推进共享核心与桌面控制器的计时器，无需真实等待。
class FakeTimers {
  FakeTimers(this._tester);
  final WidgetTester _tester;
  Future<void> elapse(Duration duration) => _tester.pump(duration);
}

/// 桌面输入测试装配：共享核心 + Fake 播放器 + Fake 全屏端口。
///
/// 在 testWidgets fake-clock zone 内构造，Fake 播放器初始位置 30 秒
/// （右键短按 Seek 到 35 秒的断言依据）。断言通过公开命令与 fake 追踪
/// 列表进行，不直接操作底层控制器。
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

  /// 桌面输入状态机别名（与测试命名一致）。
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

/// 记录页面关闭请求次数的 spy：闭包按引用捕获同一实例，断言读取最新值。
class RequestCloseSpy {
  int count = 0;
}

/// 构建桌面输入测试装配；[fake] 未传时用默认 Fake（位置 30 秒）。
///
/// [isPlaying] 为 false 时初始化后立即暂停（测试暂停态）。共享播放状态
/// 不自动转发给桌面控制器（页面在真实运行时会转发），需要模拟页面转发的
/// 用例手动调用 `desktop.onPlaybackStateChanged()`。
Future<DesktopHarness> createDesktopHarness({
  required WidgetTester tester,
  FakeVideoPlayerController? fake,
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
  final fullscreen = FakeVideoFullscreenController();
  final closeRequests = RequestCloseSpy();
  final desktop = DesktopVideoInteractionController(
    playback: playback,
    fullscreen: fullscreen,
    onRequestClose: () async => closeRequests.count++,
    onInteractionChanged: () {},
  );
  await playback.initialize();
  if (!isPlaying) {
    playback.togglePlayPause();
  }
  // 初始化会调用 setPlaybackSpeed(1.0)/play() 等命令，清空追踪列表建立干净基线。
  player.setPlaybackSpeedCalls.clear();
  player.seekToCalls.clear();
  player.setVolumeCalls.clear();
  player.playCallCount = 0;
  player.pauseCallCount = 0;
  return DesktopHarness(
    playback: playback,
    fake: player,
    fullscreen: fullscreen,
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

/// 按 debugName 匹配同名物理键；与 KeyEventSimulator 内部推断一致。
/// 找不到时用无效 HID code 兜底（测试只关心 logicalKey 分发）。
PhysicalKeyboardKey _physicalKeyFor(LogicalKeyboardKey key) {
  for (final physical in PhysicalKeyboardKey.knownPhysicalKeys) {
    if (physical.debugName == key.debugName) return physical;
  }
  return PhysicalKeyboardKey(0);
}

void main() {
  // testWidgets 会在挂起 Timer 检查之后再运行 addTearDown，无法及时取消
  // 共享核心持有的自动隐藏/提示计时器，因此各用例在断言后主动 dispose
  // （dispose 幂等，addTearDown 仍作为异常路径的兜底）。

  group('右方向键短按/长按互斥', () {
    testWidgets('右方向键四百毫秒前松开只快进五秒', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);

      await tester.pump(_rightHoldThresholdBefore);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, [const Duration(seconds: 35)]);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('右方向键达到四百毫秒只临时三倍速且松开恢复', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);

      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0]);

      harness.keyUp(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
      harness.playback.dispose();
    });

    testWidgets('右方向键 repeat 保持 pending 不改变短按分类', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      harness.repeat(LogicalKeyboardKey.arrowRight);
      harness.repeat(LogicalKeyboardKey.arrowRight);

      await tester.pump(_rightHoldThresholdBefore);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, [const Duration(seconds: 35)]);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('右方向键 repeat 保持 longHold 不重复申请倍速', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      harness.repeat(LogicalKeyboardKey.arrowRight);
      harness.repeat(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.setPlaybackSpeedCalls, [3.0]);
      harness.keyUp(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
      harness.playback.dispose();
    });
  });

  group('无法加速时长为按的收口', () {
    testWidgets('暂停时长按达到四百毫秒不加速且松开不补 Seek', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.playback.togglePlayPause();
      expect(harness.playback.state.isPlaying, isFalse);

      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('播放结束时长按达到四百毫秒不加速且松开不补 Seek', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(minutes: 5)
        ..fakeIsCompleted = true;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);
      expect(harness.playback.state.hasEnded, isTrue);

      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('错误时长按达到四百毫秒不加速且松开不补 Seek', (tester) async {
      final fake = FakeVideoPlayerController(
        initializeError: Exception('加载失败'),
      );
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);
      expect(harness.playback.state.hasError, isTrue);

      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });
  });

  group('取消路径对迟到 KeyUp 的收口', () {
    testWidgets('pending 中表面失焦取消计时器且迟到 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);

      harness.desktop.onSurfaceFocusLost();
      await tester.pump(_rightHoldThreshold);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('hold 中窗口失焦释放临时倍速且迟到 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0]);

      harness.desktop.onWindowBlur();
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);

      harness.keyUp(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
      harness.playback.dispose();
    });

    testWidgets('hold 中 cancelForRetry 释放临时倍速且迟到 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);

      harness.desktop.cancelForRetry();
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);

      harness.keyUp(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      harness.playback.dispose();
    });

    testWidgets('hold 中播放结束释放临时倍速且迟到 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      harness.keyDown(LogicalKeyboardKey.arrowRight);
      await tester.pump(_rightHoldThreshold);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0]);

      harness.desktop.onPlaybackEnded();
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);

      harness.keyUp(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      expect(harness.fake.setPlaybackSpeedCalls, [3.0, 1.0]);
      harness.playback.dispose();
    });

    testWidgets('pending 中 dispose 取消计时器且迟到 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      harness.keyDown(LogicalKeyboardKey.arrowRight);

      harness.desktop.dispose();
      await tester.pump(_rightHoldThreshold);
      harness.keyUp(LogicalKeyboardKey.arrowRight);

      expect(harness.fake.seekToCalls, isEmpty);
      harness.playback.dispose();
    });
  });

  group('方向键与音量', () {
    testWidgets('左方向键 down 立即快退五秒且 repeat 不重复 Seek', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.keyDown(LogicalKeyboardKey.arrowLeft);
      expect(harness.fake.seekToCalls, [const Duration(seconds: 25)]);

      harness.repeat(LogicalKeyboardKey.arrowLeft);
      harness.repeat(LogicalKeyboardKey.arrowLeft);
      harness.keyUp(LogicalKeyboardKey.arrowLeft);

      expect(harness.fake.seekToCalls, [const Duration(seconds: 25)]);
      harness.playback.dispose();
    });

    testWidgets('上下方向键 down 与 repeat 每次调整音量百分之五', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.5;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.keyDown(LogicalKeyboardKey.arrowUp);
      expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
      harness.repeat(LogicalKeyboardKey.arrowUp);
      expect(harness.fake.setVolumeCalls.last, closeTo(0.60, 0.0001));

      harness.keyDown(LogicalKeyboardKey.arrowDown);
      expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
      harness.repeat(LogicalKeyboardKey.arrowDown);
      expect(harness.fake.setVolumeCalls.last, closeTo(0.50, 0.0001));

      harness.keyUp(LogicalKeyboardKey.arrowUp);
      harness.keyUp(LogicalKeyboardKey.arrowDown);
      expect(harness.fake.setVolumeCalls.length, 4);
      harness.playback.dispose();
    });
  });

  group('播放命令与页面按键', () {
    testWidgets('Space 与媒体键只 down 生效且 repeat 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.keyDown(LogicalKeyboardKey.space);
      expect(harness.fake.pauseCallCount, 1);
      harness.keyDown(LogicalKeyboardKey.mediaPlayPause);
      expect(harness.fake.playCallCount, 1);

      harness.repeat(LogicalKeyboardKey.space);
      harness.repeat(LogicalKeyboardKey.mediaPlayPause);
      harness.keyUp(LogicalKeyboardKey.space);
      harness.keyUp(LogicalKeyboardKey.mediaPlayPause);

      expect(harness.fake.pauseCallCount, 1);
      expect(harness.fake.playCallCount, 1);
      harness.playback.dispose();
    });

    testWidgets('M 调用共享静音命令且 repeat 与 KeyUp 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.pageKeyDown(LogicalKeyboardKey.keyM);
      expect(harness.playback.state.isMuted, isTrue);
      expect(harness.fake.setVolumeCalls.last, 0.0);

      harness.pageKeyRepeat(LogicalKeyboardKey.keyM);
      harness.pageKeyUp(LogicalKeyboardKey.keyM);
      expect(harness.playback.state.isMuted, isTrue);
      harness.playback.dispose();
    });

    testWidgets('F 切换原生全屏并同步 actual 与 desired', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.pageKeyDown(LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(harness.fullscreen.calls, ['toggle']);
      expect(harness.fullscreen.desired, isTrue);
      expect(harness.fullscreen.actual, isTrue);
      harness.playback.dispose();
    });

    testWidgets('全屏切换失败显示固定文案且不伪造全屏状态', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.fullscreen.failNext = true;
      harness.pageKeyDown(LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(harness.fullscreen.calls, ['toggle']);
      expect(harness.fullscreen.desired, isFalse);
      expect(harness.fullscreen.actual, isFalse);
      expect(
        harness.playback.state.centerFeedback,
        isA<VideoOperationFailureFeedback>().having(
          (value) => value.message,
          'message',
          '无法切换全屏',
        ),
      );
      harness.playback.dispose();
    });

    testWidgets('M 与 F 的 repeat 无副作用', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.pageKeyRepeat(LogicalKeyboardKey.keyM);
      harness.pageKeyRepeat(LogicalKeyboardKey.keyF);
      harness.pageKeyUp(LogicalKeyboardKey.keyM);
      harness.pageKeyUp(LogicalKeyboardKey.keyF);

      expect(harness.playback.state.isMuted, isFalse);
      expect(harness.fullscreen.calls, isEmpty);
      harness.playback.dispose();
    });
  });

  group('Escape 回退', () {
    testWidgets('全屏时 Escape 只退出全屏且不请求关闭页面', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.pageKeyDown(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(harness.fullscreen.desired, isTrue);

      harness.pageKeyDown(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(harness.fullscreen.calls, ['toggle', 'exitIfFullscreen']);
      expect(harness.fullscreen.desired, isFalse);
      expect(harness.fullscreen.actual, isFalse);
      expect(harness.closeRequestCount, 0);
      harness.playback.dispose();
    });

    testWidgets('窗口模式 Escape 请求一次关闭且 repeat 与 KeyUp 不重复请求', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.pageKeyDown(LogicalKeyboardKey.escape);
      harness.pageKeyRepeat(LogicalKeyboardKey.escape);
      harness.pageKeyUp(LogicalKeyboardKey.escape);

      expect(harness.closeRequestCount, 1);
      expect(harness.fullscreen.calls, isEmpty);
      harness.playback.dispose();
    });
  });

  testWidgets('已识别 repeat/up 返回 handled 且未映射键返回 ignored', (tester) async {
    final harness = await createDesktopHarness(tester: tester);
    addTearDown(harness.desktop.dispose);

    expect(
      harness.repeat(LogicalKeyboardKey.arrowRight),
      KeyEventResult.handled,
    );
    expect(
      harness.keyUp(LogicalKeyboardKey.arrowRight),
      KeyEventResult.handled,
    );
    expect(harness.keyDown(LogicalKeyboardKey.keyZ), KeyEventResult.ignored);
    expect(
      harness.pageKeyDown(LogicalKeyboardKey.keyZ),
      KeyEventResult.ignored,
    );
    expect(
      harness.pageKeyRepeat(LogicalKeyboardKey.keyF),
      KeyEventResult.handled,
    );
    harness.playback.dispose();
  });

  group('鼠标活动与光标显隐', () {
    testWidgets('播放中鼠标活动显示控件与光标并在三秒静止后同时隐藏', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);

      harness.controller.onPointerActivity();
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);

      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isFalse);
      expect(harness.controller.isCursorVisible, isFalse);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('控制栏悬停或控件焦点均阻止自动隐藏', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);
      harness.controller.onControlsPointerEnter();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);

      harness.controller.onControlsPointerExit();
      harness.controller.onControlsFocusChanged(true);
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('悬停退出但控件焦点仍在时不释放保持', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);
      harness.controller.onControlsPointerEnter();
      harness.controller.onControlsFocusChanged(true);
      harness.controller.onControlsPointerExit();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('暂停状态不启动空闲隐藏计时', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: false,
      );
      addTearDown(harness.desktop.dispose);
      expect(harness.playback.state.isPlaying, isFalse);
      harness.controller.onPointerActivity();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('播放结束状态不启动空闲隐藏计时', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(minutes: 5)
        ..fakeIsCompleted = true;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);
      expect(harness.playback.state.hasEnded, isTrue);
      harness.controller.onPointerActivity();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.playback.state.controlsVisible, isTrue);
      expect(harness.controller.isCursorVisible, isTrue);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('播放恢复后从最后一次活动重新计时', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);
      harness.controller.onPointerActivity();
      await harness.timers.elapse(const Duration(seconds: 2));
      expect(harness.controller.isCursorVisible, isTrue);

      // 暂停：保持可见并取消空闲计时（模拟页面转发播放状态变化）
      harness.playback.togglePlayPause();
      harness.desktop.onPlaybackStateChanged();
      await harness.timers.elapse(const Duration(seconds: 2));
      expect(harness.controller.isCursorVisible, isTrue);

      // 恢复播放：从恢复时点重新开始三秒计时
      harness.playback.togglePlayPause();
      harness.desktop.onPlaybackStateChanged();
      await harness.timers.elapse(const Duration(seconds: 2));
      expect(harness.controller.isCursorVisible, isTrue);
      await harness.timers.elapse(const Duration(seconds: 1));
      expect(harness.controller.isCursorVisible, isFalse);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('窗口失焦取消光标计时并恢复可见', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);
      harness.controller.onPointerActivity();
      await harness.timers.elapse(const Duration(seconds: 1));

      harness.controller.onWindowBlur();
      expect(harness.controller.isCursorVisible, isTrue);
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.controller.isCursorVisible, isTrue); // 计时已取消
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('重试与 dispose 取消光标计时并恢复可见', (tester) async {
      final harness = await createDesktopHarness(
        tester: tester,
        isPlaying: true,
      );
      addTearDown(harness.desktop.dispose);
      harness.controller.onPointerActivity();
      await harness.timers.elapse(const Duration(seconds: 1));

      harness.controller.cancelForRetry();
      expect(harness.controller.isCursorVisible, isTrue);
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.controller.isCursorVisible, isTrue);

      harness.controller.dispose();
      await harness.timers.elapse(const Duration(seconds: 3));
      expect(harness.controller.isCursorVisible, isTrue);
      harness.playback.dispose();
    });
  });

  group('滚轮音量', () {
    testWidgets('垂直滚轮向上调高百分之五并显示实际音量反馈', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.5;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
      expect(
        harness.playback.state.centerFeedback,
        isA<VideoVolumeFeedback>().having(
          (v) => v.volume,
          'volume',
          closeTo(0.55, 0.0001),
        ),
      );
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('垂直滚轮向下调低百分之五', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.5;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, 1)),
      );
      expect(harness.fake.setVolumeCalls.last, closeTo(0.45, 0.0001));
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('纯水平或横向主导滚轮完全忽略', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(1, 0)),
      );
      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(2, 1)),
      );
      expect(harness.fake.setVolumeCalls, isEmpty);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('五十毫秒内后续滚轮事件被忽略，到期后下一事件立即生效', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.5;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.length, 1);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.length, 1);

      await harness.timers.elapse(_wheelThrottleWindow);
      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.length, 2);
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('滚轮音量钳制在零到一之间', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.05;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, 1)),
      );
      expect(harness.fake.setVolumeCalls.last, closeTo(0.0, 0.0001));
      await harness.timers.elapse(_wheelThrottleWindow);
      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, 1)),
      );
      expect(harness.fake.setVolumeCalls.length, 1); // 已到 0，不重复写
      expect(harness.playback.state.volume, closeTo(0.0, 0.0001));
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('滚轮音量钳制在上限不重复写底层', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30)
        ..fakeVolume = 0.95;
      final harness = await createDesktopHarness(tester: tester, fake: fake);
      addTearDown(harness.desktop.dispose);

      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.last, closeTo(1.0, 0.0001));
      await harness.timers.elapse(_wheelThrottleWindow);
      harness.controller.handlePointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -1)),
      );
      expect(harness.fake.setVolumeCalls.length, 1); // 已到 1，不重复写
      expect(harness.playback.state.volume, closeTo(1.0, 0.0001));
      harness.desktop.dispose();
      harness.playback.dispose();
    });

    testWidgets('非滚轮指针信号不抛异常也不改变状态', (tester) async {
      final harness = await createDesktopHarness(tester: tester);
      addTearDown(harness.desktop.dispose);
      final volumeBefore = harness.playback.state.volume;

      harness.controller.handlePointerSignal(PointerScaleEvent());
      expect(harness.playback.state.volume, volumeBefore);
      expect(harness.fake.setVolumeCalls, isEmpty);
      harness.desktop.dispose();
      harness.playback.dispose();
    });
  });
}
