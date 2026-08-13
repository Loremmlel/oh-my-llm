import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_video_controller_factory.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/video_player_controls.dart';

import '../../../../helpers/widget_test_animation.dart';
import '../../helpers/fake_video_player_controller.dart';

// ── 测试助手 ─────────────────────────────────────────────────────────

/// 测试用的远端资源（避免真实平台通道，控制器一律经 factory 注入 Fake）。
NetworkMediaResource _testResource() =>
    NetworkMediaResource(Uri.parse('http://localhost/test.mp4'));

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
///
/// [mediaQuery] 非空时注入宿主 MediaQuery（路由内覆盖，播放器可见字段
/// 逐项生效），用于模拟 systemGestureInsets 等系统边缘环境。
Widget _buildTestPageWithFake({
  required FakeVideoPlayerController fakeController,
  MediaVideoControllerFactory? controllerFactory,
  MediaQueryData? mediaQuery,
}) {
  Widget page = VideoPlayerPage(
    resource: _testResource(),
    fileName: 'test-video.mp4',
    controllerFactory: controllerFactory ?? (resource) => fakeController,
  );
  if (mediaQuery != null) {
    page = MediaQuery(data: mediaQuery, child: page);
  }
  return _wrapWithMaterialApp(page);
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
              resource: _testResource(),
              fileName: 'test-video.mp4',
              controllerFactory: (resource) => fakeController,
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
      // 记录到达 factory 的资源：重试必须复用同一资源对象
      final factoryCalls = <MediaResource>[];
      await tester.pumpWidget(
        _buildTestPageWithFake(
          fakeController: failingController,
          controllerFactory: (resource) {
            factoryCalls.add(resource);
            return failingController;
          },
        ),
      );
      // 首次失败
      await failingController.waitForInitializeCount(1);
      await tester.pump();

      // 错误页可见：错误图标、错误文案与重试按钮
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('视频加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // 点击重试 → 第二次初始化。重试按钮与全屏手势层是兄弟层，
      // tap 不再被双击识别器拖延：单帧内即可观察第二次初始化
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(failingController.initializeCallCount, 2);

      // fake 持续抛出初始化错误，重试后仍处于同一可恢复错误状态，
      // 但重试按钮仍可用，说明重试流程完整执行
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 同一资源对象到达 factory 两次（首次进入 + 重试）
      expect(factoryCalls, hasLength(2));
      expect(factoryCalls[0], factoryCalls[1]);
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
          // 点击暂停按钮使视频暂停（控制栏与手势层是兄弟层，tap 即时生效）
          await tester.tap(find.byIcon(Icons.pause));
          await tester.pump();
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
          expect(semanticsByTooltip('关闭视频'), findsNothing, reason: c.name);
        }
        await gesture.up();
        await tester.pump();
        await settleAnimatedWidgetTransition(tester);

        if (c.expectedClamp != null) {
          expect(fake.seekToCalls.last, c.expectedClamp, reason: c.name);
        } else {
          // 正常拖动：松手后控制栏恢复可见，seek 已执行
          expect(semanticsByTooltip('关闭视频'), findsOneWidget, reason: c.name);
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
  // 关闭按钮
  // ═══════════════════════════════════════════════════════════════════

  group('关闭按钮', () {
    testWidgets('点击顶部关闭按钮 pop 路由后一帧释放播放器', (tester) async {
      await tester.pumpWidget(
        _buildPushedTestPageWithFake(fakeController: fakeController),
      );
      await tester.tap(find.text('打开播放器'));
      await _pumpInit(tester, controller: fakeController);

      // 通过顶部关闭按钮（tooltip「关闭视频」）触发 pop，替代页面级
      // Navigator 操作。控制栏与手势层是兄弟层：按钮 tap 不再被双击
      // 识别器拖延，路由 pop 后一帧即释放播放器
      await tester.tap(find.byTooltip('关闭视频'));
      await tester.pump();
      await tester.pump();

      expect(fakeController.disposeCount, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 顶部控制按钮
  // ═══════════════════════════════════════════════════════════════════

  group('顶部控制按钮', () {
    testWidgets('点击音量按钮后单帧内弹出音量弹窗', (tester) async {
      await tester.pumpWidget(
        _buildTestPageWithFake(fakeController: fakeController),
      );
      await _pumpInit(tester, controller: fakeController);

      // 顶部控制栏与手势层是兄弟层：音量按钮 tap 立即派发，
      // 弹窗应紧随一次 tap 的下一帧出现，不再受双击窗口拖延
      await tester.tap(find.byTooltip('音量，当前 100%'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 系统手势边缘与拖动取消
  // ═══════════════════════════════════════════════════════════════════

  group('系统手势边缘', () {
    // 带左右 system gesture inset 的宿主环境：与 MediaQueryData 同源，
    // 播放器可见字段（size / systemGestureInsets）逐项生效
    const edgeMediaQuery = MediaQueryData(
      size: Size(400, 800),
      systemGestureInsets: EdgeInsets.only(left: 24, right: 24),
    );

    /// 在 400×800 逻辑视口 + 左右 24px 手势边缘的宿主下完成初始化。
    Future<void> pumpPlayerInEdgeViewport(
      WidgetTester tester,
      FakeVideoPlayerController fake,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _buildTestPageWithFake(
          fakeController: fake,
          mediaQuery: edgeMediaQuery,
        ),
      );
      await _pumpInit(tester, controller: fake);
    }

    testWidgets('从系统手势边缘内开始横拖超过 slop 仍不 seek', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await pumpPlayerInEdgeViewport(tester, fake);

      // x=5 位于左手势边缘（24px）内：手势 overlay 收缩后不覆盖该区域，
      // 简单横拖应被忽略，边缘拖动让位给系统返回手势
      final gesture = await tester.startGesture(const Offset(5, 400));
      await gesture.moveBy(const Offset(kDragSlopDefault, 0));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(fake.seekToCalls, isEmpty);
      await _flushGestureTimers(tester);
    });

    testWidgets('从手势边缘之间开始横拖仍能 seek', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await pumpPlayerInEdgeViewport(tester, fake);

      // x=200 位于左右手势边缘之间：普通横拖不受影响
      final gesture = await tester.startGesture(const Offset(200, 400));
      final slop = const Offset(kDragSlopDefault, 0);
      await gesture.moveBy(slop);
      await gesture.moveBy(const Offset(100, 0) - slop);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(fake.seekToCalls, isNotEmpty);
      await _flushGestureTimers(tester);
    });

    testWidgets('拖动被系统取消时不 seek，回滚预览并恢复控制栏', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await pumpPlayerInEdgeViewport(tester, fake);

      final gesture = await tester.startGesture(const Offset(200, 400));
      final slop = const Offset(kDragSlopDefault, 0);
      await gesture.moveBy(slop);
      await gesture.moveBy(const Offset(100, 0) - slop);
      await tester.pump();

      // 拖动中：seek 预览可见，控制栏隐藏
      final seekHint = find.semantics.byPredicate(
        (node) => node.label.startsWith('预览位置'),
      );
      expect(seekHint, findsOneWidget);
      expect(semanticsByTooltip('关闭视频'), findsNothing);

      // 系统取消（如 Android 返回手势抢占触摸）：不提交 seek，
      // 预览消失，控制栏恢复到手势前可见状态
      await gesture.cancel();
      await tester.pump();

      expect(fake.seekToCalls, isEmpty);
      expect(seekHint, findsNothing);
      expect(semanticsByTooltip('关闭视频'), findsOneWidget);
      await _flushGestureTimers(tester);
    });

    testWidgets('拖动手势在接受前被取消，不污染下一次完整横拖的 seek', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await pumpPlayerInEdgeViewport(tester, fake);

      // 手势 A：拖动接受前即被系统取消（如触摸瞬间的中断），
      // 应不留任何残留状态
      final cancelled = await tester.startGesture(const Offset(200, 400));
      await cancelled.cancel();
      await tester.pump();

      // 手势 B：完整横拖以 up 结束，必须正常提交 seek
      final gesture = await tester.startGesture(const Offset(200, 400));
      final slop = const Offset(kDragSlopDefault, 0);
      await gesture.moveBy(slop);
      await gesture.moveBy(const Offset(100, 0) - slop);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(fake.seekToCalls, isNotEmpty);
      await _flushGestureTimers(tester);
    });

    testWidgets('非 16:9 视口下播放表面保持等比，手势层仍覆盖全屏', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await pumpPlayerInEdgeViewport(tester, fake);

      // 视频按 16:9 等比渲染（AspectRatio 尺寸含焦点边框 2px 内缩），
      // 不被 400×800 视口拉伸成 400×800
      final videoSize = tester.getSize(find.byType(AspectRatio));
      expect(videoSize.height, closeTo(videoSize.width * 9 / 16, 0.1));

      // 视频区域之外（中央 y=120，位于等比视频上方）仍属全屏手势层：
      // 横拖照常 seek，证明 overlay 不随视频等比收缩
      final gesture = await tester.startGesture(const Offset(200, 120));
      final slop = const Offset(kDragSlopDefault, 0);
      await gesture.moveBy(slop);
      await gesture.moveBy(const Offset(100, 0) - slop);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(fake.seekToCalls, isNotEmpty);
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
