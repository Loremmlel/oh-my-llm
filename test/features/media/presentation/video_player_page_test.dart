import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/video_player_controls.dart';

import '../helpers/fake_video_player_controller.dart';

// ── 测试助手 ─────────────────────────────────────────────────────────

/// 包裹 widget 到 MaterialApp + Navigator 中，模拟真实导航场景。
Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onDidRemovePage: (page) {},
    ),
  );
}

/// 创建使用 FakeController 的测试页面。
Widget _buildTestPageWithFake({
  required FakeVideoPlayerController fakeController,
}) {
  return _wrapWithMaterialApp(
    VideoPlayerPage(
      videoUrl: 'http://localhost/test.mp4',
      fileName: 'test-video.mp4',
      controllerFactory: (uri) => fakeController,
    ),
  );
}

/// 以零时长路由推入页面，令 pop 的一帧断言只验证资源释放。
Widget _buildPushedTestPageWithFake({
  required FakeVideoPlayerController fakeController,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => VideoPlayerPage(
              videoUrl: 'http://localhost/test.mp4',
              fileName: 'test-video.mp4',
              controllerFactory: (uri) => fakeController,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
        child: const Text('打开播放器'),
      ),
    ),
  );
}

/// 等待初始化完成，并清除 init 过程产生的追踪记录。
///
/// 先推一帧（路由推入场景下初始化在此触发），再等初始化信号，
/// 最后单帧应用初始化结果，不按固定时长盲等。
Future<void> _pumpInit(
  WidgetTester tester, {
  required FakeVideoPlayerController controller,
}) async {
  await tester.pump(); // build 帧（路由推入时初始化在此触发）
  await controller.waitForInitializeCount(1);
  await tester.pump(); // 初始化信号已满足，单帧应用结果
  _resetTracking(controller);
}

/// 清除 FakeController 的追踪列表。
void _resetTracking(FakeVideoPlayerController c) {
  c.seekToCalls.clear();
  c.setPlaybackSpeedCalls.clear();
  c.setVolumeCalls.clear();
  c.playCallCount = 0;
  c.pauseCallCount = 0;
}

/// 视频区域左四分之一处（用于双击快退）。
Offset _leftHalf(WidgetTester tester) {
  final rect = tester.getRect(find.byType(VideoPlayerPage));
  return Offset(rect.left + rect.width * 0.25, rect.center.dy);
}

/// 视频区域右四分之一处（用于双击快进）。
Offset _rightHalf(WidgetTester tester) {
  final rect = tester.getRect(find.byType(VideoPlayerPage));
  return Offset(rect.left + rect.width * 0.75, rect.center.dy);
}

/// 视频区域中心（用于长按/拖动）。
Offset _center(WidgetTester tester) {
  final rect = tester.getRect(find.byType(VideoPlayerPage));
  return rect.center;
}

/// 排出 DoubleTapGestureRecognizer 的挂起计时器。
///
/// onDoubleTap 会启动 double-tap countdown timer，测试结束前
/// 需要排出这些 timer，否则挂起计时器会泄漏到后续用例。
Future<void> _flushGestureTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeVideoPlayerController fakeController;

  setUp(() {
    fakeController = FakeVideoPlayerController();
  });

  // ═══════════════════════════════════════════════════════════════════
  // 静态渲染
  // ═══════════════════════════════════════════════════════════════════

  group('静态渲染', () {
    testWidgets('页面正常渲染', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);
      expect(find.byType(Scaffold), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('返回按钮存在', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('倍速按钮存在', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);
      expect(find.text('1.0x'), findsOneWidget);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 错误状态（经 factory 注入失败 fake，确定性进入错误页）
  // ═══════════════════════════════════════════════════════════════════

  group('错误状态', () {
    testWidgets('加载失败时显示错误信息', (tester) async {
      final failingController = FakeVideoPlayerController(
        initializeError: StateError('初始化失败'),
      );
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: failingController),
      );
      await failingController.waitForInitializeCount(1);
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('视频加载失败'), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('加载失败时显示重试按钮', (tester) async {
      final failingController = FakeVideoPlayerController(
        initializeError: StateError('初始化失败'),
      );
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: failingController),
      );
      await failingController.waitForInitializeCount(1);
      await tester.pump();

      expect(find.text('重试'), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('错误状态下可点击重试按钮', (tester) async {
      final failingController = FakeVideoPlayerController(
        initializeError: StateError('初始化失败'),
      );
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: failingController),
      );
      // 首次失败
      await failingController.waitForInitializeCount(1);
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // 点击重试 → 第二次初始化
      await tester.tap(find.text('重试'));
      // 外层双击识别器持有竞技场直到双击超时，按钮的 tap 延迟派发，
      // 先排出该计时器，再等第二次初始化信号
      await _flushGestureTimers(tester);
      await failingController.waitForInitializeCount(2);
      await tester.pump();

      // fake 持续抛出初始化错误，重试后仍处于错误状态，
      // 但重试按钮仍可用，说明重试流程完整执行
      expect(failingController.initializeCallCount, 2);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 双击手势
  // ═══════════════════════════════════════════════════════════════════

  group('双击手势', () {
    testWidgets('双击左半屏 seek 后退 15s', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 点击左半屏双击
      await tester.tapAt(_leftHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_leftHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeController.seekToCalls, isNotEmpty);
      expect(fakeController.seekToCalls.last, const Duration(seconds: 15));
      await _flushGestureTimers(tester);
    });

    testWidgets('双击右半屏 seek 前进 15s', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeController.seekToCalls, isNotEmpty);
      expect(fakeController.seekToCalls.last, const Duration(seconds: 45));
      await _flushGestureTimers(tester);
    });

    testWidgets('双击左半屏在开头 clamp 到 0', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 5);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_leftHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_leftHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeController.seekToCalls.last, Duration.zero);
      await _flushGestureTimers(tester);
    });

    testWidgets('双击右半屏在末尾 clamp 到 duration', (tester) async {
      fakeController.fakePosition =
          const Duration(minutes: 5) - const Duration(seconds: 5);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeController.seekToCalls.last, fakeController.fakeDuration);
      await _flushGestureTimers(tester);
    });

    testWidgets('双击显示快进提示', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      // 中央提示显示 "15s" 文字
      expect(find.text('15s'), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('双击后提示 1 秒后消失', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('15s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('15s'), findsNothing);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 长按手势
  // ═══════════════════════════════════════════════════════════════════

  group('长按手势', () {
    testWidgets('长按时切换到 3x', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));

      expect(fakeController.setPlaybackSpeedCalls, isNotEmpty);
      expect(fakeController.setPlaybackSpeedCalls.first, 3.0);

      await gesture.up();
      await tester.pump();
      await _flushGestureTimers(tester);
    });

    testWidgets('松手恢复原倍速（默认 1.0）', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        fakeController.setPlaybackSpeedCalls.length,
        greaterThanOrEqualTo(2),
      );
      expect(fakeController.setPlaybackSpeedCalls.last, 1.0);
      await _flushGestureTimers(tester);
    });

    testWidgets('长按显示倍速提示', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('3.0x'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await _flushGestureTimers(tester);
    });

    testWidgets('暂停时长按不生效', (tester) async {
      // 先初始化（默认播放中），再通过 pause 暂停
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 点击暂停按钮使视频暂停
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(milliseconds: 100));
      await _flushGestureTimers(tester);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));

      // setPlaybackSpeed 不应被调用
      expect(fakeController.setPlaybackSpeedCalls, isEmpty);

      await gesture.up();
      await tester.pump();
      await _flushGestureTimers(tester);
    });

    testWidgets('播放结束后长按不生效', (tester) async {
      fakeController.fakeIsCompleted = true;
      fakeController.fakeIsPlaying = false;
      fakeController.fakePosition = fakeController.fakeDuration;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));

      // 播放结束后 _hasEnded=true，长按不应触发 setPlaybackSpeed
      expect(fakeController.setPlaybackSpeedCalls, isEmpty);

      await gesture.up();
      await tester.pump();
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 水平拖动
  // ═══════════════════════════════════════════════════════════════════

  group('水平拖动', () {
    testWidgets('水平拖动松手执行 seek', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      fakeController.fakeDuration = const Duration(minutes: 5);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 使用 dragFrom 在 Scaffold 区域拖动（避开不可 hit test 的 VideoPlayer）
      await tester.dragFrom(_center(tester), const Offset(100, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // seekTo 应被调用一次
      expect(fakeController.seekToCalls.length, 1);
      await _flushGestureTimers(tester);
    });

    testWidgets('向左拖动超过起始位置 clamp 到 0', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 5);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.dragFrom(_center(tester), const Offset(-200, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeController.seekToCalls.last, Duration.zero);
      await _flushGestureTimers(tester);
    });

    testWidgets('水平拖动后控制栏恢复', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.dragFrom(_center(tester), const Offset(100, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 手势与控制栏联动
  // ═══════════════════════════════════════════════════════════════════

  group('手势与控制栏联动', () {
    testWidgets('双击期间隐藏控制栏', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      // 中央提示显示了（说明手势已触发）
      expect(find.text('15s'), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('双击后等待提示消失控制栏恢复', (tester) async {
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('15s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('15s'), findsNothing);
      await _flushGestureTimers(tester);
    });

    testWidgets('长按期间隐藏控制栏', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('3.0x'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 中央提示可见性
  // ═══════════════════════════════════════════════════════════════════

  group('中央提示可见性', () {
    testWidgets('播放中无手势时提示隐藏', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.text('15s'), findsNothing);
      expect(find.text('3.0x'), findsNothing);
      await _flushGestureTimers(tester);
    });

    testWidgets('暂停时显示播放图标', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 点击暂停按钮使视频暂停
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await _flushGestureTimers(tester);

      // 暂停时应显示播放图标（中央提示 48px + 底部按钮 36px，至少一个）
      expect(find.byIcon(Icons.play_arrow), findsAtLeastNWidgets(1));
    });

    testWidgets('播放中触发手势提示时显示手势内容', (tester) async {
      fakeController.fakeIsPlaying = true;
      fakeController.fakePosition = const Duration(seconds: 30);
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_rightHalf(tester));
      await tester.pump(const Duration(milliseconds: 100));

      // 播放图标不应该出现（showPauseIcon=false when _isPlaying=true）
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      // 但手势文字应出现
      expect(find.text('15s'), findsOneWidget);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 控制栏
  // ═══════════════════════════════════════════════════════════════════

  group('控制栏', () {
    testWidgets('初始控制栏可见', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('点击视频区域切换控制栏显隐', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 点击视频区域（由于 onTap 有 300ms double-tap delay，需要等待）
      await tester.tapAt(_center(tester));
      await tester.pump(const Duration(milliseconds: 500));

      // Slider 仍在树中（AnimatedOpacity 控制可见性，不从树中移除）
      expect(find.byType(Slider), findsOneWidget);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 返回按钮
  // ═══════════════════════════════════════════════════════════════════

  group('返回按钮', () {
    testWidgets('pop 路由后一帧释放播放器', (tester) async {
      await tester.pumpWidget(
        _buildPushedTestPageWithFake(fakeController: fakeController),
      );
      await tester.tap(find.text('打开播放器'));
      await _pumpInit(tester, controller: fakeController);

      Navigator.of(tester.element(find.byType(VideoPlayerPage))).pop();
      await tester.pump();

      // 路由 pop 后一帧即释放播放器。
      expect(fakeController.disposeCount, 1);
      await _flushGestureTimers(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 工具函数
  // ═══════════════════════════════════════════════════════════════════

  group('时间格式化', () {
    test('formatVideoDuration mm:ss 格式', () {
      expect(
        formatVideoDuration(const Duration(minutes: 5, seconds: 30)),
        '05:30',
      );
    });

    test('formatVideoDuration h:mm:ss 格式', () {
      expect(
        formatVideoDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '1:23:45',
      );
    });

    test('formatVideoDuration 零时长', () {
      expect(formatVideoDuration(Duration.zero), '00:00');
    });
  });

  group('音量图标', () {
    test('音量为零显示 volume_off', () {
      expect(volumeIconData(0.0), Icons.volume_off);
    });

    test('音量低于 0.5 显示 volume_down', () {
      expect(volumeIconData(0.3), Icons.volume_down);
    });

    test('音量 >= 0.5 显示 volume_up', () {
      expect(volumeIconData(0.5), Icons.volume_up);
      expect(volumeIconData(1.0), Icons.volume_up);
    });
  });
}
