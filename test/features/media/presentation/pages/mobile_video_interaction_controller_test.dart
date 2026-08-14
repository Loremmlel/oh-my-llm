import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/presentation/pages/mobile_video_interaction_controller.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_playback_controller.dart';

import '../../helpers/fake_video_player_controller.dart';

// ── 测试助手 ─────────────────────────────────────────────────────────

/// Mobile 输入测试合体：输入控制器 + 共享核心 + Fake 播放器。
///
/// 初始化后清空追踪记录，让断言只看测试内的输入调用；fake 位置固定为
/// 30 秒，供双击/横拖的相对位移断言使用。
class MobileVideoInteractionHarness {
  MobileVideoInteractionHarness({
    required this.interaction,
    required this.playback,
    required this.fake,
  });

  final MobileVideoInteractionController interaction;
  final VideoPlaybackController playback;
  final FakeVideoPlayerController fake;

  /// 用例收尾：释放共享核心与输入控制器持有的计时器。
  ///
  /// testWidgets 在挂起 Timer 检查之后才运行 addTearDown，无法及时取消
  /// 自动隐藏/提示计时器，因此各用例在断言后主动调用（dispose 幂等，
  /// addTearDown 仍作为异常路径的兜底）。
  void dispose() {
    interaction.dispose();
    playback.dispose();
  }
}

Future<MobileVideoInteractionHarness> createMobileHarness() async {
  final fake = FakeVideoPlayerController()
    ..fakePosition = const Duration(seconds: 30);
  final playback = VideoPlaybackController(
    resource: NetworkMediaResource(Uri.parse('http://localhost/test.mp4')),
    controllerFactory: (resource) => fake,
    onStateChanged: () {},
  );
  await playback.initialize();
  fake.seekToCalls.clear();
  fake.setPlaybackSpeedCalls.clear();
  fake.setVolumeCalls.clear();
  fake.playCallCount = 0;
  fake.pauseCallCount = 0;
  final interaction = MobileVideoInteractionController(playback: playback);
  addTearDown(interaction.dispose);
  addTearDown(playback.dispose);
  return MobileVideoInteractionHarness(
    interaction: interaction,
    playback: playback,
    fake: fake,
  );
}

void main() {
  group('双击左右半屏', () {
    final seekCases = <({double x, double width, Duration expected})>[
      (x: 100.0, width: 400.0, expected: const Duration(seconds: -15)),
      (x: 300.0, width: 400.0, expected: const Duration(seconds: 15)),
    ];

    for (final testCase in seekCases) {
      testWidgets('双击左右半屏继续按 15 秒调用共享 Seek', (tester) async {
        final harness = await createMobileHarness();
        harness.interaction.updateScreenWidth(testCase.width);
        harness.interaction.handleDoubleTapDown(
          TapDownDetails(globalPosition: Offset(testCase.x, 100)),
        );
        harness.interaction.handleDoubleTap();
        expect(
          harness.fake.seekToCalls.last,
          const Duration(seconds: 30) + testCase.expected,
        );
        harness.dispose();
      });
    }
  });

  group('长按临时倍速', () {
    testWidgets('暂停或播放结束时长按不申请临时倍速', (tester) async {
      final cases = <({String name, bool pause, bool ended})>[
        (name: '暂停', pause: true, ended: false),
        (name: '播放结束', pause: false, ended: true),
      ];

      for (final c in cases) {
        final harness = await createMobileHarness();
        if (c.pause) {
          await harness.fake.pause();
        }
        if (c.ended) {
          await harness.fake.seekTo(harness.fake.fakeDuration);
          await harness.fake.pause();
        }

        harness.interaction.handleLongPressStart(LongPressStartDetails());
        expect(harness.fake.setPlaybackSpeedCalls, isEmpty, reason: c.name);
        harness.interaction.handleLongPressEnd(LongPressEndDetails());
        harness.dispose();
      }
    });

    testWidgets('长按后松开恢复最新常驻倍速', (tester) async {
      final harness = await createMobileHarness();
      harness.playback.setPersistentSpeed(1.5);

      harness.interaction.handleLongPressStart(LongPressStartDetails());
      expect(harness.fake.setPlaybackSpeedCalls.last, 3.0);

      harness.interaction.handleLongPressEnd(LongPressEndDetails());
      expect(harness.fake.setPlaybackSpeedCalls.last, 1.5);
      harness.dispose();
    });
  });

  group('水平拖动', () {
    testWidgets('update 不 seek，end 提交一次，cancel 不提交', (tester) async {
      final harness = await createMobileHarness();
      harness.interaction.updateScreenWidth(400);

      harness.interaction.handleHorizontalDragStart(
        DragStartDetails(globalPosition: const Offset(100, 100)),
      );
      harness.interaction.handleHorizontalDragUpdate(
        DragUpdateDetails(globalPosition: const Offset(300, 100)),
      );
      expect(harness.fake.seekToCalls, isEmpty);

      harness.interaction.handleHorizontalDragEnd(DragEndDetails());
      expect(harness.fake.seekToCalls, hasLength(1));

      harness.interaction.handleHorizontalDragStart(
        DragStartDetails(globalPosition: const Offset(100, 100)),
      );
      harness.interaction.handleHorizontalDragUpdate(
        DragUpdateDetails(globalPosition: const Offset(300, 100)),
      );
      harness.interaction.handleHorizontalDragCancel();
      expect(harness.fake.seekToCalls, hasLength(1));
      harness.dispose();
    });

    testWidgets('取消标志不污染下一次横拖的 seek', (tester) async {
      final harness = await createMobileHarness();
      harness.interaction.updateScreenWidth(400);

      harness.interaction.handleHorizontalDragStart(
        DragStartDetails(globalPosition: const Offset(100, 100)),
      );
      harness.interaction.handleHorizontalDragCancel();
      expect(harness.fake.seekToCalls, isEmpty);

      harness.interaction.handleHorizontalDragStart(
        DragStartDetails(globalPosition: const Offset(100, 100)),
      );
      harness.interaction.handleHorizontalDragUpdate(
        DragUpdateDetails(globalPosition: const Offset(200, 100)),
      );
      harness.interaction.handleHorizontalDragEnd(DragEndDetails());
      expect(harness.fake.seekToCalls, hasLength(1));
      harness.dispose();
    });
  });
}
