import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../helpers/fake_video_player_controller.dart';
import '../../helpers/fake_video_player_platform_bindings.dart';

/// 测试用的远端资源（避免真实平台通道，控制器一律经 factory 注入 Fake）。
NetworkMediaResource _testResource() =>
    NetworkMediaResource(Uri.parse('http://localhost/test.mp4'));

/// 桌面页面测试装配：共享 fake 播放器、fake 全屏端口与当前 tester。
class DesktopVideoTestHarness {
  DesktopVideoTestHarness({
    required this.fake,
    required this.fullscreen,
    required this.tester,
  });

  final FakeVideoPlayerController fake;
  final FakeVideoFullscreenController fullscreen;
  final WidgetTester tester;

  /// 播放表面焦点节点：surface Focus 是 VideoPlayer 最近的 Focus 祖先。
  FocusNode get surfaceFocusNode {
    final focus = tester.widget<Focus>(
      find
          .ancestor(of: find.byType(VideoPlayer), matching: find.byType(Focus))
          .first,
    );
    return focus.focusNode!;
  }
}

/// 包裹 widget 到 MaterialApp + Navigator，模拟真实导航场景。
Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onDidRemovePage: (page) {},
    ),
  );
}

/// 以 Desktop bindings 组装页面并等待初始化完成。
Future<DesktopVideoTestHarness> pumpDesktopVideo(
  WidgetTester tester, {
  Duration position = const Duration(seconds: 30),
}) async {
  final fake = FakeVideoPlayerController()..fakePosition = position;
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

/// 以 Desktop bindings 推入页面，底部留「打开播放器」按钮供 pop 断言。
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
  group('Desktop 初始焦点', () {
    testWidgets('初始化成功后播放表面自动获得主焦点', (tester) async {
      final harness = await pumpDesktopVideo(tester);
      expect(harness.surfaceFocusNode.hasPrimaryFocus, isTrue);
    });
  });

  group('Desktop 方向键', () {
    testWidgets('左右键按五秒且右键短按在 KeyUp 执行', (tester) async {
      final harness = await pumpDesktopVideo(
        tester,
        position: const Duration(seconds: 30),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls.last, const Duration(seconds: 35));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      expect(harness.fake.seekToCalls.last, const Duration(seconds: 30));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    });

    testWidgets('表面失焦取消右键分类，迟到 KeyUp 不执行短按', (tester) async {
      final harness = await pumpDesktopVideo(
        tester,
        position: const Duration(seconds: 30),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      // Tab 把焦点从表面移到控制栏：pending 右键被取消，不 Seek
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.fake.seekToCalls, isEmpty);
    });

    testWidgets('控制栏持有焦点时方向键不被表面抢走', (tester) async {
      final harness = await pumpDesktopVideo(
        tester,
        position: const Duration(seconds: 30),
      );
      // Tab 从表面进入顶部控制栏，方向键交给控件/traversal 处理
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(harness.fake.seekToCalls, isEmpty);
    });
  });

  group('Desktop 音量与静音', () {
    testWidgets('M 静音并恢复，上下键按百分之五调音', (tester) async {
      final harness = await pumpDesktopVideo(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(harness.fake.setVolumeCalls.last, 0.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(harness.fake.setVolumeCalls.last, closeTo(1.0, 0.0001));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(harness.fake.setVolumeCalls.last, closeTo(0.95, 0.0001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(harness.fake.setVolumeCalls.last, closeTo(1.0, 0.0001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    });
  });

  group('Desktop 全屏', () {
    testWidgets('F 切换原生全屏', (tester) async {
      final harness = await pumpDesktopVideo(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(harness.fullscreen.calls, contains('toggle'));
      expect(harness.fullscreen.actualFullscreen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(harness.fullscreen.actualFullscreen, isFalse);
    });

    testWidgets('全屏切换失败显示固定文案，不关闭页面也不暂停视频', (tester) async {
      final harness = await pumpDesktopVideo(tester);
      harness.fullscreen.failNext = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(find.text('无法切换全屏'), findsOneWidget);
      expect(find.byType(VideoPlayerPage), findsOneWidget);
      expect(harness.fake.pauseCallCount, 0);
    });

    testWidgets('全屏 Escape 只退出全屏，再次 Escape 才关闭页面', (tester) async {
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

    testWidgets('顶部关闭 await 全屏恢复后再退出页面', (tester) async {
      final harness = await pumpPushedDesktopVideo(tester, fullscreen: true);
      await tester.tap(find.byTooltip('关闭视频'));
      await tester.pump();
      await tester.pump();
      expect(harness.fullscreen.calls, contains('restoreAndDispose'));
      expect(find.text('打开播放器'), findsOneWidget);
      expect(harness.fake.disposeCount, 1);
    });

    testWidgets('关闭恢复失败仍继续退出页面', (tester) async {
      final harness = await pumpPushedDesktopVideo(tester);
      harness.fullscreen.failRestore = true;
      await tester.tap(find.byTooltip('关闭视频'));
      await tester.pump();
      await tester.pump();
      expect(find.text('打开播放器'), findsOneWidget);
    });
  });

  group('Desktop 弹层优先', () {
    testWidgets('音量弹窗打开时 Escape 只关闭弹窗，不退出页面', (tester) async {
      await pumpPushedDesktopVideo(tester);
      await tester.tap(find.byTooltip('音量，当前 100%'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(VideoPlayerPage), findsOneWidget);
    });
  });
}
