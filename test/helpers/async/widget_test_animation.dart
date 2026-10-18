import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/animation.dart';

const _animationFrameStep = Duration(milliseconds: 100);

/// 背景仍在流式加载时，只等待目标弹窗动画，不等待全局帧停止。
Future<void> settleStreamingOverlayTransition(
  WidgetTester tester,
  Animation<double> animation,
  AnimationStatus status,
) async {
  for (var frame = 0; animation.status != status && frame < 20; frame++) {
    await tester.pump(_animationFrameStep);
  }
  if (animation.status != status) throw StateError('弹窗动画未在 2 秒内结束');
}
