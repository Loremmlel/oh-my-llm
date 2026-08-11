import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/video_player_controls.dart';

import '../../../helpers/widget_test_animation.dart';
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

/// 逻辑视口尺寸（物理像素 / devicePixelRatio）。
Size _logicalViewport(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// 视频区域左四分之一处（用于双击快退）。
///
/// 按逻辑视口 25% 宽度定位：描述公开手势分区而非子组件矩形。
Offset _leftHalf(WidgetTester tester) {
  final size = _logicalViewport(tester);
  return Offset(size.width * 0.25, size.height * 0.5);
}

/// 视频区域右四分之一处（用于双击快进）。
///
/// 按逻辑视口 75% 宽度定位：描述公开手势分区而非子组件矩形。
Offset _rightHalf(WidgetTester tester) {
  final size = _logicalViewport(tester);
  return Offset(size.width * 0.75, size.height * 0.5);
}

/// 视频区域中心（用于长按/拖动）。
///
/// 按逻辑视口 50% 中心定位：描述公开手势分区而非子组件矩形。
Offset _center(WidgetTester tester) {
  final size = _logicalViewport(tester);
  return Offset(size.width * 0.5, size.height * 0.5);
}

/// 按 tooltip 语义属性定位语义节点。
///
/// 控制栏隐藏时整体退出语义树，因此「找到/找不到」即其可见性证据。
SemanticsFinder semanticsByTooltip(String tooltip) =>
    find.semantics.byPredicate((node) => node.tooltip == tooltip);

/// 排出 DoubleTapGestureRecognizer 的挂起计时器。
///
/// 单击后识别器启动 double-tap countdown timer，需推进双击窗口
/// （kDoubleTapTimeout）让计时器到期，否则挂起计时器会泄漏到后续用例。
Future<void> _flushGestureTimers(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout);
}

void main() {
  late FakeVideoPlayerController fakeController;

  setUp(() {
    fakeController = FakeVideoPlayerController();
  });

  // ═══════════════════════════════════════════════════════════════════
  // 错误状态（经 factory 注入失败 fake，确定性进入错误页）
  // ═══════════════════════════════════════════════════════════════════

  group('错误状态', () {
    testWidgets('加载失败显示错误信息，点击重试后再次初始化', (tester) async {
      final failingController = FakeVideoPlayerController(
        initializeError: StateError('初始化失败'),
      );
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: failingController),
      );
      // 首次失败
      await failingController.waitForInitializeCount(1);
      await tester.pump();

      // 错误页可见：错误图标、错误文案与重试按钮
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('视频加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // 点击重试 → 第二次初始化
      await tester.tap(find.text('重试'));
      // 外层双击识别器持有竞技场直到双击超时，按钮的 tap 延迟派发，
      // 先排出该计时器，再等第二次初始化信号
      await _flushGestureTimers(tester);
      await failingController.waitForInitializeCount(2);
      await tester.pump();

      // fake 持续抛出初始化错误，重试后仍处于同一可恢复错误状态，
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
    testWidgets('双击左右半屏 seek 相对 15s 并 clamp，快进提示 1 秒后消失', (tester) async {
      final cases =
          <
            ({
              String name,
              Offset Function(WidgetTester) zone,
              Duration position,
              Duration expected,
              bool verifyHint,
            })
          >[
            (
              name: '左半屏快退',
              zone: _leftHalf,
              position: const Duration(seconds: 30),
              expected: const Duration(seconds: 15),
              verifyHint: false,
            ),
            (
              name: '右半屏快进',
              zone: _rightHalf,
              position: const Duration(seconds: 30),
              expected: const Duration(seconds: 45),
              verifyHint: true,
            ),
            (
              name: '开头快退 clamp 到 0',
              zone: _leftHalf,
              position: const Duration(seconds: 5),
              expected: Duration.zero,
              verifyHint: false,
            ),
            (
              name: '末尾快进 clamp 到 duration',
              zone: _rightHalf,
              position: const Duration(minutes: 5) - const Duration(seconds: 5),
              expected: const Duration(minutes: 5),
              verifyHint: false,
            ),
          ];

      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final fake = FakeVideoPlayerController();
        fake.fakePosition = c.position;
        await tester.pumpWidget(_buildTestPageWithFake(fakeController: fake));
        await _pumpInit(tester, controller: fake);

        await tester.tapAt(c.zone(tester));
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(c.zone(tester));
        await tester.pump(kDoubleTapMinTime);

        expect(fake.seekToCalls.last, c.expected, reason: c.name);
        if (c.verifyHint) {
          // 快进提示可见，1 秒后消失
          expect(find.text('15s'), findsOneWidget, reason: c.name);
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.text('15s'), findsNothing, reason: c.name);
        }
        await _flushGestureTimers(tester);
        if (i < cases.length - 1) {
          // 行间卸载整棵旧树：同型页面重复 pump 会复用 State 而不重新
          // 初始化，新 fake 将永远等不到 initialize；空树保证全新挂载
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 长按手势
  // ═══════════════════════════════════════════════════════════════════

  group('长按手势', () {
    testWidgets('长按切换 3.0x 并显示提示，松手恢复 1.0x', (tester) async {
      fakeController.fakeIsPlaying = true;
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      final gesture = await tester.startGesture(_center(tester));
      await tester.pump(kLongPressTimeout);

      // 长按期间：倍速切换到 3.0，提示可见
      expect(fakeController.setPlaybackSpeedCalls, [3.0]);
      expect(find.text('3.0x'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      // 松手恢复原倍速
      expect(fakeController.setPlaybackSpeedCalls, [3.0, 1.0]);
      await _flushGestureTimers(tester);
    });

    testWidgets('暂停或播放结束时长按不切换倍速', (tester) async {
      final cases = <({String name, bool pauseBefore, bool completed})>[
        (name: '暂停', pauseBefore: true, completed: false),
        (name: '播放结束', pauseBefore: false, completed: true),
      ];

      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final fake = FakeVideoPlayerController();
        if (c.completed) {
          fake.fakeIsCompleted = true;
          fake.fakeIsPlaying = false;
          fake.fakePosition = fake.fakeDuration;
        }
        await tester.pumpWidget(_buildTestPageWithFake(fakeController: fake));
        await _pumpInit(tester, controller: fake);

        if (c.pauseBefore) {
          // 点击暂停按钮使视频暂停（按钮 tap 在双击窗口中由 flush 排定）
          await tester.tap(find.byIcon(Icons.pause));
          await tester.pump();
          await _flushGestureTimers(tester);
        }

        final gesture = await tester.startGesture(_center(tester));
        await tester.pump(kLongPressTimeout);

        // setPlaybackSpeed 不应被调用
        expect(fake.setPlaybackSpeedCalls, isEmpty, reason: c.name);

        await gesture.up();
        await tester.pump();
        await _flushGestureTimers(tester);
        if (i < cases.length - 1) {
          // 行间卸载旧树，避免同型页面复用 State 导致新 fake 无法初始化
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 水平拖动
  // ═══════════════════════════════════════════════════════════════════

  group('水平拖动', () {
    testWidgets('水平拖动按位移 seek 并恢复控制栏，起点处 clamp 到 0', (tester) async {
      final cases =
          <
            ({
              String name,
              Duration position,
              Offset offset,
              Duration? expectedClamp,
            })
          >[
            (
              name: '正常拖动',
              position: const Duration(seconds: 30),
              offset: const Offset(100, 0),
              expectedClamp: null,
            ),
            (
              name: '起点 clamp',
              position: const Duration(seconds: 5),
              offset: const Offset(-200, 0),
              expectedClamp: Duration.zero,
            ),
          ];

      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final fake = FakeVideoPlayerController();
        fake.fakePosition = c.position;
        fake.fakeDuration = const Duration(minutes: 5);
        await tester.pumpWidget(_buildTestPageWithFake(fakeController: fake));
        await _pumpInit(tester, controller: fake);

        final gesture = await tester.startGesture(_center(tester));
        // 先移过 slop 阈值让拖动被接受（该事件只触发 onStart），再继续
        // 移动产生 onUpdate；单次大幅 moveBy 不会有更新事件
        final slop = Offset(kDragSlopDefault * c.offset.dx.sign, 0);
        await gesture.moveBy(slop);
        await gesture.moveBy(c.offset - slop);
        await tester.pump();
        if (c.expectedClamp == null) {
          // 拖动进行中控制栏隐藏：其 tooltip 节点退出语义树
          expect(semanticsByTooltip('返回'), findsNothing, reason: c.name);
        }
        await gesture.up();
        await tester.pump();
        await settleAnimatedWidgetTransition(tester);

        if (c.expectedClamp != null) {
          expect(fake.seekToCalls.last, c.expectedClamp, reason: c.name);
        } else {
          // 正常拖动：松手后控制栏恢复可见，seek 已执行
          expect(semanticsByTooltip('返回'), findsOneWidget, reason: c.name);
          expect(fake.seekToCalls, isNotEmpty, reason: c.name);
        }
        await _flushGestureTimers(tester);
        if (i < cases.length - 1) {
          // 行间卸载旧树，避免同型页面复用 State 导致新 fake 无法初始化
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 返回按钮
  // ═══════════════════════════════════════════════════════════════════

  group('返回按钮', () {
    testWidgets('点击顶部返回按钮 pop 路由后一帧释放播放器', (tester) async {
      await tester.pumpWidget(
        _buildPushedTestPageWithFake(fakeController: fakeController),
      );
      await tester.tap(find.text('打开播放器'));
      await _pumpInit(tester, controller: fakeController);

      // 通过顶部返回按钮（tooltip「返回」）触发 pop，替代页面级 Navigator 操作
      await tester.tap(find.byTooltip('返回'));
      // 外层双击识别器持有竞技场直到双击超时，按钮的 tap 延迟派发，
      // 先推进窗口再 pop 移除页面的一帧
      await tester.pump(kDoubleTapTimeout);
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
    test('formatVideoDuration 按时长切换 mm:ss 与 h:mm:ss', () {
      final cases = <({String name, Duration input, String expected})>[
        (
          name: 'mm:ss',
          input: const Duration(minutes: 5, seconds: 30),
          expected: '05:30',
        ),
        (
          name: 'h:mm:ss',
          input: const Duration(hours: 1, minutes: 23, seconds: 45),
          expected: '1:23:45',
        ),
        (name: '零时长', input: Duration.zero, expected: '00:00'),
      ];
      for (final c in cases) {
        expect(formatVideoDuration(c.input), c.expected, reason: c.name);
      }
    });
  });

  group('音量图标', () {
    test('volumeIconData 按音量分档', () {
      final cases = <({String name, double volume, IconData icon})>[
        (name: '零音量', volume: 0.0, icon: Icons.volume_off),
        (name: '低音量', volume: 0.3, icon: Icons.volume_down),
        (name: '中音量', volume: 0.5, icon: Icons.volume_up),
        (name: '满音量', volume: 1.0, icon: Icons.volume_up),
      ];
      for (final c in cases) {
        expect(volumeIconData(c.volume), c.icon, reason: c.name);
      }
    });
  });
}
