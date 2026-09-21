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

/// 等待一次有限的 Route/GoRouter 导航动画（push/pop/redirect）结束。
Future<void> settleRouteTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 Dialog、Menu、BottomSheet、Drawer 的开合动画结束。
Future<void> settleOverlayTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 TabController / TabBarView 的切换动画结束。
Future<void> settleTabTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 PageView、ballistic scroll、scroll-to-bottom 的滚动动画结束。
Future<void> settleScrollMotion(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 AnimatedCrossFade、AnimatedSize、rail 展开收起等有限组件动画结束。
Future<void> settleAnimatedWidgetTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 全仓唯一直接调用 pumpAndSettle 的位置。
///
/// 100ms 步进与 Flutter 默认一致，能结束常见有限动画而不多渲染中间帧；
/// 2 秒超时是"有限动画没有结束"的失败保护，不代表测试需要等满 2 秒。
/// 不导入生产动画时长，不提供通用
/// settle API——等待对象必须由调用方命名。
Future<void> _settleFiniteAnimation(WidgetTester tester) {
  return tester.pumpAndSettle(
    _animationFrameStep,
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}
