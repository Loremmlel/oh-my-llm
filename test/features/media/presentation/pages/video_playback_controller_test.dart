import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_state.dart';

import '../../helpers/fake_video_player_controller.dart';

/// 用同一个 Fake 工厂构建共享播放核心。
VideoPlaybackController createPlaybackController(
  FakeVideoPlayerController fake,
) {
  return VideoPlaybackController(
    resource: NetworkMediaResource(Uri.parse('http://localhost/test.mp4')),
    controllerFactory: (resource) => fake,
    onStateChanged: () {},
  );
}

/// 构建已初始化的核心与 Fake，并在初始化前预置底层音量。
///
/// [initialVolume] 写入 fake 的底层音量，使核心初始化从 controller value
/// 投影出该音量（与真实播放器从平台投影音量一致）。
Future<({VideoPlaybackController controller, FakeVideoPlayerController fake})>
createPlaybackHarness({double initialVolume = 1.0}) async {
  final fake = FakeVideoPlayerController()..fakeVolume = initialVolume;
  final controller = createPlaybackController(fake);
  await controller.initialize();
  return (controller: controller, fake: fake);
}

void main() {
  // testWidgets 会在挂起 Timer 检查之后再运行 addTearDown，无法及时取消
  // 共享核心持有的自动隐藏/提示计时器，因此各用例在断言后主动 dispose
  // （dispose 幂等，addTearDown 仍作为异常路径的兜底）。

  testWidgets('初始化后自动播放并投影时长位置与缓冲状态', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 30)
      ..fakeDuration = const Duration(minutes: 5);
    final controller = createPlaybackController(fake);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state.isInitialized, isTrue);
    expect(controller.state.isPlaying, isTrue);
    expect(controller.state.currentPosition, const Duration(seconds: 30));
    expect(fake.playCallCount, 1);
    controller.dispose();
  });

  testWidgets('相对 Seek 使用最新位置并在首尾边界 clamp', (tester) async {
    final fake = FakeVideoPlayerController()
      ..fakePosition = const Duration(seconds: 2);
    final controller = createPlaybackController(fake);
    addTearDown(controller.dispose);
    await controller.initialize();
    fake.seekToCalls.clear();

    controller.seekRelative(const Duration(seconds: -5));
    expect(fake.seekToCalls.last, Duration.zero);
    expect(
      controller.state.centerFeedback,
      isA<VideoRelativeSeekFeedback>()
          .having((value) => value.delta, 'delta', const Duration(seconds: -5))
          .having((value) => value.target, 'target', Duration.zero),
    );
    controller.dispose();
  });

  testWidgets('相对 Seek 反馈被临时倍速替换时恢复此前控制栏状态', (tester) async {
    final harness = await createPlaybackHarness();
    addTearDown(harness.controller.dispose);

    harness.controller.seekRelative(const Duration(seconds: 5));
    expect(harness.controller.state.controlsVisible, isFalse);

    final lease = harness.controller.beginTemporarySpeed(3.0)!;

    expect(harness.controller.state.controlsVisible, isTrue);
    expect(
      harness.controller.state.centerFeedback,
      isA<VideoTemporarySpeedFeedback>(),
    );
    harness.controller.endTemporarySpeed(lease);
    harness.controller.dispose();
  });

  testWidgets('相对 Seek 后开始拖动时旧提示计时器不清除拖动预览', (tester) async {
    final harness = await createPlaybackHarness();
    addTearDown(harness.controller.dispose);

    harness.controller.seekRelative(const Duration(seconds: 5));
    harness.controller.onSeekStart(0.5);
    await tester.pump(const Duration(seconds: 1));

    expect(harness.controller.state.isDragging, isTrue);
    expect(
      harness.controller.state.centerFeedback,
      isA<VideoSeekPreviewFeedback>().having(
        (feedback) => feedback.target,
        'target',
        const Duration(minutes: 2, seconds: 30),
      ),
    );
    harness.controller.onSeekCancel();
    harness.controller.dispose();
  });

  testWidgets('错误 lease 不能结束当前临时倍速且常驻倍速更新后再恢复', (tester) async {
    final fake = FakeVideoPlayerController();
    final controller = createPlaybackController(fake);
    addTearDown(controller.dispose);
    await controller.initialize();

    final stale = controller.beginTemporarySpeed(3.0)!;
    controller.endTemporarySpeed(stale);
    final active = controller.beginTemporarySpeed(3.0)!;
    controller.setPersistentSpeed(1.5);
    controller.endTemporarySpeed(stale);
    expect(fake.fakePlaybackSpeed, 3.0);

    controller.endTemporarySpeed(active);
    expect(fake.fakePlaybackSpeed, 1.5);
    controller.dispose();
  });

  group('临时倍速在播放状态变化时自动释放', () {
    testWidgets('播放自然结束自动恢复常驻倍速', (tester) async {
      final fake = FakeVideoPlayerController()
        ..fakePosition = const Duration(seconds: 30);
      final controller = createPlaybackController(fake);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.beginTemporarySpeed(3.0);
      expect(controller.state.effectiveSpeed, 3.0);
      expect(fake.fakePlaybackSpeed, 3.0);

      // 播放自然结束：底层置为 completed 并推进到近末尾位置
      fake.fakeIsCompleted = true;
      fake.fakePosition = fake.fakeDuration;
      fake.emitValueChanged();

      expect(controller.state.hasEnded, isTrue);
      expect(controller.state.effectiveSpeed, 1.0);
      expect(fake.fakePlaybackSpeed, 1.0);
      controller.dispose();
    });

    testWidgets('临时加速中暂停立即恢复常驻倍速', (tester) async {
      final harness = await createPlaybackHarness();
      addTearDown(harness.controller.dispose);
      harness.controller.beginTemporarySpeed(3.0);
      expect(harness.controller.state.effectiveSpeed, 3.0);
      expect(harness.fake.fakePlaybackSpeed, 3.0);

      harness.controller.togglePlayPause();
      expect(harness.controller.state.isPlaying, isFalse);
      expect(harness.controller.state.effectiveSpeed, 1.0);
      expect(harness.fake.fakePlaybackSpeed, 1.0);
      harness.controller.dispose();
    });
  });

  group('音量与静音', () {
    testWidgets('普通步进边界正确 clamp 音量', (tester) async {
      final cases = [
        (start: 0.98, delta: 0.05, expected: 1.0),
        (start: 0.02, delta: -0.05, expected: 0.0),
        (start: 0.50, delta: 0.05, expected: 0.55),
      ];
      for (final c in cases) {
        final harness = await createPlaybackHarness(initialVolume: c.start);
        addTearDown(harness.controller.dispose);
        harness.controller.adjustVolume(c.delta);
        expect(
          harness.fake.setVolumeCalls.last,
          closeTo(c.expected, 0.0001),
          reason: 'start=${c.start} delta=${c.delta}',
        );
        harness.controller.dispose();
      }
    });

    testWidgets('M 静音后再次切换恢复最后非零音量', (tester) async {
      final harness = await createPlaybackHarness(initialVolume: 0.65);
      addTearDown(harness.controller.dispose);
      harness.controller.toggleMute();
      expect(harness.controller.state.isMuted, isTrue);
      expect(harness.fake.setVolumeCalls.last, 0.0);

      harness.controller.toggleMute();
      expect(harness.controller.state.isMuted, isFalse);
      expect(harness.fake.setVolumeCalls.last, 0.65);
      harness.controller.dispose();
    });

    testWidgets('显式静音时调音先恢复记忆音量再应用步进', (tester) async {
      final harness = await createPlaybackHarness(initialVolume: 0.60);
      addTearDown(harness.controller.dispose);
      harness.controller.toggleMute();
      harness.controller.adjustVolume(-0.05);
      expect(harness.controller.state.isMuted, isFalse);
      expect(harness.fake.setVolumeCalls.last, closeTo(0.55, 0.0001));
      harness.controller.dispose();
    });

    testWidgets('手动零音量不覆盖记忆且上调从百分之五开始', (tester) async {
      final harness = await createPlaybackHarness(initialVolume: 0.60);
      addTearDown(harness.controller.dispose);
      harness.controller.setVolume(0);
      expect(harness.controller.state.lastNonZeroVolume, 0.60);
      expect(harness.controller.state.isMuted, isFalse);
      harness.controller.adjustVolume(0.05);
      expect(harness.fake.setVolumeCalls.last, 0.05);
      harness.controller.dispose();
    });

    testWidgets('边界无变化时不重复调用底层音量 setter', (tester) async {
      final harness = await createPlaybackHarness(initialVolume: 0.5);
      addTearDown(harness.controller.dispose);
      harness.controller.setVolume(0.5);
      harness.controller.adjustVolume(0.0);
      expect(harness.fake.setVolumeCalls, isEmpty);
      harness.controller.dispose();
    });
  });

  testWidgets('showOperationFailure 显示固定失败反馈', (tester) async {
    final harness = await createPlaybackHarness();
    addTearDown(harness.controller.dispose);

    harness.controller.showOperationFailure('无法切换全屏');
    expect(
      harness.controller.state.centerFeedback,
      isA<VideoOperationFailureFeedback>().having(
        (value) => value.message,
        'message',
        '无法切换全屏',
      ),
    );
    harness.controller.dispose();
  });
}
