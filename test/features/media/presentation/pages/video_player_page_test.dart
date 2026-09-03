import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/media_video_controller_factory.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

NetworkMediaResource _testResource() =>
    NetworkMediaResource(Uri.parse('http://localhost/test.mp4'));

VideoPlayerPlatformBindings _mobileTestBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onDidRemovePage: (page) {},
    ),
  );
}

Widget _buildTestPageWithFake({
  required FakeVideoPlayerController fakeController,
  MediaVideoControllerFactory? controllerFactory,
  MediaQueryData? mediaQuery,
  VideoPlayerPlatformBindingsFactory? bindingsFactory,
}) {
  Widget page = VideoPlayerPage(
    resource: _testResource(),
    fileName: 'test-video.mp4',
    controllerFactory: controllerFactory ?? (resource) => fakeController,
    platformBindingsFactory: bindingsFactory ?? _mobileTestBindings,
  );
  if (mediaQuery != null) {
    page = MediaQuery(data: mediaQuery, child: page);
  }
  return _wrapWithMaterialApp(page);
}

Widget _buildPushedTestPageWithFake({
  required FakeVideoPlayerController fakeController,
  VideoPlayerPlatformBindingsFactory? bindingsFactory,
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
              platformBindingsFactory: bindingsFactory ?? _mobileTestBindings,
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

Future<void> _pumpInit(
  WidgetTester tester, {
  required FakeVideoPlayerController controller,
}) async {
  await tester.pump();
  await controller.waitForInitializeCount(1);
  await tester.pump();
  controller.seekToCalls.clear();
  controller.setPlaybackSpeedCalls.clear();
  controller.setVolumeCalls.clear();
  controller.playCallCount = 0;
  controller.pauseCallCount = 0;
}

Size _logicalViewport(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

Offset _rightHalf(WidgetTester tester) {
  final size = _logicalViewport(tester);
  return Offset(size.width * 0.75, size.height * 0.5);
}

Offset _center(WidgetTester tester) {
  final size = _logicalViewport(tester);
  return Offset(size.width * 0.5, size.height * 0.5);
}

SemanticsFinder semanticsByTooltip(String tooltip) =>
    find.semantics.byPredicate((node) => node.tooltip == tooltip);

Future<void> _flushGestureTimers(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout);
}

void main() {
  late FakeVideoPlayerController fakeController;

  setUp(() {
    fakeController = FakeVideoPlayerController();
  });

  testWidgets('加载失败显示错误并允许重试初始化', (tester) async {
    final failingController = FakeVideoPlayerController(
      initializeError: StateError('初始化失败'),
    );
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
    await failingController.waitForInitializeCount(1);
    await tester.pump();

    expect(find.textContaining('视频加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(failingController.initializeCallCount, 2);
    expect(find.text('重试'), findsOneWidget);
    expect(factoryCalls, hasLength(2));
    expect(factoryCalls[0], factoryCalls[1]);
  });

  testWidgets('右半屏双击快进并显示短暂反馈', (tester) async {
    fakeController.fakePosition = const Duration(seconds: 30);
    await tester.pumpWidget(
      _buildTestPageWithFake(fakeController: fakeController),
    );
    await _pumpInit(tester, controller: fakeController);

    await tester.tapAt(_rightHalf(tester));
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(_rightHalf(tester));
    await tester.pump(kDoubleTapMinTime);

    expect(fakeController.seekToCalls.last, const Duration(seconds: 45));
    expect(find.text('15s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('15s'), findsNothing);
    await _flushGestureTimers(tester);
  });

  testWidgets('长按临时三倍速并在松手后恢复', (tester) async {
    fakeController.fakeIsPlaying = true;
    await tester.pumpWidget(
      _buildTestPageWithFake(fakeController: fakeController),
    );
    await _pumpInit(tester, controller: fakeController);

    final gesture = await tester.startGesture(_center(tester));
    await tester.pump(kLongPressTimeout);
    expect(fakeController.setPlaybackSpeedCalls, [3.0]);
    expect(find.text('3.0x'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(fakeController.setPlaybackSpeedCalls, [3.0, 1.0]);
    await _flushGestureTimers(tester);
  });

  testWidgets('水平拖动提交 Seek 并恢复控制栏', (tester) async {
    fakeController.fakePosition = const Duration(seconds: 30);
    await tester.pumpWidget(
      _buildTestPageWithFake(fakeController: fakeController),
    );
    await _pumpInit(tester, controller: fakeController);

    final gesture = await tester.startGesture(_center(tester));
    final slop = const Offset(kDragSlopDefault, 0);
    await gesture.moveBy(slop);
    await gesture.moveBy(const Offset(100, 0) - slop);
    await tester.pump();
    expect(semanticsByTooltip('关闭视频'), findsNothing);

    await gesture.up();
    await tester.pump();
    await settleAnimatedWidgetTransition(tester);
    expect(fakeController.seekToCalls, isNotEmpty);
    expect(semanticsByTooltip('关闭视频'), findsOneWidget);
    await _flushGestureTimers(tester);
  });

  testWidgets('关闭页面恢复系统 UI 并释放播放器', (tester) async {
    final systemUi = FakeMobileVideoSystemUiController();
    await tester.pumpWidget(
      _buildPushedTestPageWithFake(
        fakeController: fakeController,
        bindingsFactory: () => MobileVideoPlayerBindings(systemUi: systemUi),
      ),
    );
    await tester.tap(find.text('打开播放器'));
    await _pumpInit(tester, controller: fakeController);
    expect(systemUi.calls, ['enter']);

    await tester.tap(find.byTooltip('关闭视频'));
    await tester.pump();
    await tester.pump();

    expect(systemUi.calls, ['enter', 'restore']);
    expect(fakeController.disposeCount, 1);
  });

  testWidgets('系统手势边缘内横拖不提交 Seek', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    fakeController.fakePosition = const Duration(seconds: 30);
    await tester.pumpWidget(
      _buildTestPageWithFake(
        fakeController: fakeController,
        mediaQuery: const MediaQueryData(
          size: Size(400, 800),
          systemGestureInsets: EdgeInsets.only(left: 24, right: 24),
        ),
      ),
    );
    await _pumpInit(tester, controller: fakeController);

    final gesture = await tester.startGesture(const Offset(5, 400));
    await gesture.moveBy(const Offset(kDragSlopDefault, 0));
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();

    expect(fakeController.seekToCalls, isEmpty);
    await _flushGestureTimers(tester);
  });

  testWidgets('非宽屏视口保持视频比例且手势层覆盖页面', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _buildTestPageWithFake(fakeController: fakeController),
    );
    await _pumpInit(tester, controller: fakeController);

    final videoSize = tester.getSize(find.byType(AspectRatio));
    expect(videoSize.height, closeTo(videoSize.width * 9 / 16, 0.1));

    final gesture = await tester.startGesture(const Offset(200, 120));
    final slop = const Offset(kDragSlopDefault, 0);
    await gesture.moveBy(slop);
    await gesture.moveBy(const Offset(100, 0) - slop);
    await gesture.up();
    await tester.pump();
    expect(fakeController.seekToCalls, isNotEmpty);
    await _flushGestureTimers(tester);
  });

  testWidgets('移动页面忽略桌面静音全屏和音量快捷键', (tester) async {
    fakeController.fakeVolume = 0.5;
    await tester.pumpWidget(
      _buildTestPageWithFake(fakeController: fakeController),
    );
    await _pumpInit(tester, controller: fakeController);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(fakeController.setVolumeCalls, isEmpty);
    expect(fakeController.setPlaybackSpeedCalls, isEmpty);
  });
}
