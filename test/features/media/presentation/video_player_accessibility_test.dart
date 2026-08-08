import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import '../helpers/fake_video_player_controller.dart';

/// 按 tooltip 语义属性定位语义节点（IconButton/PopupMenuButton 的 tooltip 在语义树中为 tooltip 属性）。
SemanticsFinder semanticsByTooltip(String tooltip) =>
    find.semantics.byPredicate((node) => node.tooltip == tooltip);

/// 当前持有主焦点的语义节点。
SemanticsFinder focusedNode() => find.semantics.byFlag(SemanticsFlag.isFocused);

/// 初始化即失败的 Fake：快速、确定地进入错误状态，
/// 不依赖真实网络请求的超时行为。
class _FailingVideoPlayerController extends FakeVideoPlayerController {
  @override
  Future<void> initialize() async {
    throw Exception('network error');
  }
}

/// initialize 永不完成的 Fake：让页面稳定停留在加载态。
///
/// 普通 Fake 的 initialize 在 pumpWidget 内部即随微任务完成，
/// 首个可断言帧已是播放态，加载态无法被观察到。
class _NeverInitializingVideoPlayerController
    extends FakeVideoPlayerController {
  @override
  Future<void> initialize() => Completer<void>().future;
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

/// 使用 FakeController 构建页面并完成初始化；可选设置视口。
///
/// init 完成后清空追踪记录，让断言只看测试内的调用。
Future<void> _pumpVideo(
  WidgetTester tester,
  FakeVideoPlayerController fake, {
  Size? viewport,
}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    _wrapWithMaterialApp(
      VideoPlayerPage(
        videoUrl: 'http://localhost/test.mp4',
        fileName: 'test-video.mp4',
        controllerFactory: (uri) => fake,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  fake.seekToCalls.clear();
  fake.setPlaybackSpeedCalls.clear();
  fake.playCallCount = 0;
  fake.pauseCallCount = 0;
}

/// 按 Tab 次数把焦点移动到播放表面（traversal 顺序第一个可聚焦节点）。
Future<void> _tab(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
}

void main() {
  group('viewport smoke', () {
    for (final vp in [phonePortrait, wideDesktop]) {
      testWidgets('${vp.name} 下关键控件语义完整', (tester) async {
        final fake = FakeVideoPlayerController();
        fake.fakePosition = const Duration(seconds: 30);
        await _pumpVideo(tester, fake, viewport: vp.size);

        expect(find.semantics.byLabel('视频播放器：test-video.mp4'), findsOneWidget);
        expect(semanticsByTooltip('返回'), findsOneWidget);
        expect(semanticsByTooltip('播放速度，当前 1.0 倍'), findsOneWidget);
        expect(semanticsByTooltip('音量，当前 100%'), findsOneWidget);
        expect(semanticsByTooltip('暂停'), findsOneWidget);
        expect(find.semantics.byLabel('播放进度'), findsOneWidget);
      });
    }
  });

  group('播放表面语义', () {
    testWidgets('播放中 surface 有唯一 label/value/hint/button/tap', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);

      final surface = find.semantics.byLabel('视频播放器：test-video.mp4');
      expect(surface, findsOneWidget);
      expect(
        surface,
        isSemantics(
          value: '正在播放，播放控件已显示',
          hint: '激活以隐藏播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('加载态有进度语义，不伪装成播放表面', (tester) async {
      await tester.pumpWidget(
        _wrapWithMaterialApp(
          VideoPlayerPage(
            videoUrl: 'http://localhost/test.mp4',
            fileName: 'test-video.mp4',
            controllerFactory: (uri) =>
                _NeverInitializingVideoPlayerController(),
          ),
        ),
      );
      await tester.pump(); // initialize 挂起，稳定停留在加载态
      expect(find.semantics.byLabel('正在加载视频'), findsOneWidget);
      expect(find.semantics.byLabel('视频播放器：test-video.mp4'), findsNothing);
    });

    testWidgets('semantics tap 切换控制栏显隐，隐藏后控制节点退出语义树', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);

      tester.semantics.tap(find.semantics.byLabel('视频播放器：test-video.mp4'));
      await tester.pump();

      final surface = find.semantics.byLabel('视频播放器：test-video.mp4');
      expect(
        surface,
        isSemantics(
          value: '正在播放，播放控件已隐藏',
          hint: '激活以显示播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒',
        ),
      );
      expect(semanticsByTooltip('返回'), findsNothing);
      expect(semanticsByTooltip('暂停'), findsNothing);
      expect(find.semantics.byLabel('播放进度'), findsNothing);
    });
  });

  group('播放状态与快捷键', () {
    testWidgets('Space 切换播放/暂停，按钮 tooltip 同步更新', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);
      await _tab(tester); // 聚焦播放表面

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.pauseCallCount, 1);
      expect(semanticsByTooltip('播放'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.playCallCount, 1);
      expect(semanticsByTooltip('暂停'), findsOneWidget);
    });

    testWidgets('播放结束初始状态时 Space 重播', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = fake.fakeDuration;
      fake.fakeIsCompleted = true;
      await _pumpVideo(tester, fake);
      await _tab(tester);

      expect(semanticsByTooltip('重新播放'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      // 重播 = seek 回 0 并 play
      expect(fake.seekToCalls, [Duration.zero]);
      expect(fake.playCallCount, 1);
    });

    testWidgets('ArrowLeft/ArrowRight 相对 seek 15 秒并 clamp', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await _pumpVideo(tester, fake);
      await _tab(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fake.seekToCalls.last, const Duration(seconds: 45));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(fake.seekToCalls.last, const Duration(seconds: 30));

      // 通过 seekTo 同步 state.currentPosition（直接改 fakePosition 不触发 listener），
      // 再清掉调用记录，让断言只看键盘产生的 seek。
      Future<void> moveTo(Duration position) async {
        fake.fakePosition = position;
        await fake.seekTo(position);
        fake.seekToCalls.clear();
      }

      // 边界 clamp：靠近 0 时向左快退仍回到 0
      await moveTo(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(fake.seekToCalls.last, Duration.zero);

      // 靠近结尾时向右快进仍停在 duration
      await moveTo(fake.fakeDuration - const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fake.seekToCalls.last, fake.fakeDuration);
    });
  });

  group('返回与动态状态', () {
    testWidgets('surface 聚焦时 Escape 返回上一页且 fake 只 dispose 一次', (tester) async {
      final fake = FakeVideoPlayerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => VideoPlayerPage(
                    videoUrl: 'http://localhost/test.mp4',
                    fileName: 'test-video.mp4',
                    controllerFactory: (uri) => fake,
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
      await tester.pump(const Duration(milliseconds: 100));
      fake.disposeCount = 0;
      fake.seekToCalls.clear();

      await _tab(tester); // 聚焦播放表面
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(find.text('打开播放器'), findsOneWidget);
      expect(fake.disposeCount, 1);
    });

    testWidgets('快进/快退只产生一个离散 live region，视觉 15s 不重复', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await _pumpVideo(tester, fake);
      await _tab(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      final status = find.semantics.byLabel('已快进 15 秒');
      expect(status, findsOneWidget);
      expect(status, isSemantics(isLiveRegion: true));
      expect(find.semantics.byValue('15s'), findsNothing);
    });

    testWidgets('长按产生临时倍速 live region，松手恢复原速度且不重复', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);
      fake.setPlaybackSpeedCalls.clear();

      // 长按期间断言 live region 与 3.0x；hold 状态必须用 startGesture 维持，
      // longPressAt 内部会完整走完按下-抬起，回到测试代码时提示已消失。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VideoPlayerPage)),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final status = find.semantics.byLabel('临时三倍速播放');
      expect(status, findsOneWidget);
      expect(status, isSemantics(isLiveRegion: true));
      expect(fake.setPlaybackSpeedCalls, [3.0]);

      // 松手后恢复原速度；提示消失且不生成「消失」播报
      await gesture.up();
      await tester.pump();
      expect(find.semantics.byLabel('临时三倍速播放'), findsNothing);
      expect(fake.setPlaybackSpeedCalls.last, 1.0);
    });

    testWidgets('错误状态是 live status 且重试可操作，无播放表面', (tester) async {
      await tester.pumpWidget(
        _wrapWithMaterialApp(
          VideoPlayerPage(
            videoUrl: 'http://localhost/test.mp4',
            fileName: 'test-video.mp4',
            controllerFactory: (uri) => _FailingVideoPlayerController(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // initialize 抛异常
      await tester.pump(const Duration(milliseconds: 100));

      final errorStatus = find.semantics.byPredicate(
        (node) =>
            node.flagsCollection.isLiveRegion && node.label.contains('视频加载失败'),
      );
      expect(errorStatus, findsOneWidget);
      expect(
        find.semantics.byPredicate(
          (n) =>
              n.label == '重试' &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
        findsOneWidget,
      );
      expect(find.semantics.byLabel('视频播放器：test-video.mp4'), findsNothing);
    });
  });

  group('进度 Slider 语义', () {
    testWidgets('有时长时 label/实际时间 value 与 increase/decrease', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakePosition = const Duration(seconds: 30);
      await _pumpVideo(tester, fake);

      final slider = find.semantics.byLabel('播放进度');
      expect(slider, findsOneWidget);
      expect(
        slider,
        isSemantics(
          value: '00:30 / 05:00',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
    });

    testWidgets('无时长时 disabled 且无 increase/decrease', (tester) async {
      final fake = FakeVideoPlayerController();
      fake.fakeDuration = Duration.zero;
      await _pumpVideo(tester, fake);

      final slider = find.semantics.byLabel('播放进度');
      expect(
        slider,
        isSemantics(
          hasEnabledState: true,
          isEnabled: false,
          hasIncreaseAction: false,
          hasDecreaseAction: false,
        ),
      );
    });
  });

  group('焦点顺序与焦点恢复', () {
    testWidgets('连续 Tab 顺序为 surface→返回→倍速→音量→暂停→播放进度', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);

      await _tab(tester);
      expect(focusedNode(), isSemantics(label: '视频播放器：test-video.mp4'));
      await _tab(tester);
      expect(focusedNode(), isSemantics(tooltip: '返回'));
      await _tab(tester);
      expect(focusedNode(), isSemantics(tooltip: '播放速度，当前 1.0 倍'));
      await _tab(tester);
      expect(focusedNode(), isSemantics(tooltip: '音量，当前 100%'));
      await _tab(tester);
      expect(focusedNode(), isSemantics(tooltip: '暂停'));
      await _tab(tester);
      expect(focusedNode(), isSemantics(label: '播放进度'));
    });

    testWidgets('控制聚焦时暂停自动隐藏，pump 超过 3 秒仍可见且焦点不变', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);
      await _tab(tester, 2); // 聚焦返回按钮

      await tester.pump(const Duration(seconds: 4));
      expect(semanticsByTooltip('返回'), findsOneWidget);
      expect(focusedNode(), isSemantics(tooltip: '返回'));
    });

    testWidgets('控制聚焦时 pointer tap 隐藏控制栏，下一帧焦点恢复到 surface', (tester) async {
      final fake = FakeVideoPlayerController();
      await _pumpVideo(tester, fake);
      await _tab(tester, 2); // 聚焦返回按钮

      // onTap 受 300ms double-tap 判定延迟，先推进时钟让 tap 生效，
      // 再 pump 一帧应用焦点恢复与语义更新。
      await tester.tapAt(tester.getCenter(find.byType(VideoPlayerPage)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(focusedNode(), isSemantics(label: '视频播放器：test-video.mp4'));
      expect(semanticsByTooltip('返回'), findsNothing);
    });
  });
}
