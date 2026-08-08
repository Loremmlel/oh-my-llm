import 'package:flutter_test/flutter_test.dart';

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
/// 50ms 步进比默认 250ms 更快推进有限动画；2 秒超时是"有限动画没有结束"的
/// 失败保护，不代表测试需要等满 2 秒。不导入生产动画时长，不提供通用
/// settle API——等待对象必须由调用方命名。
Future<void> _settleFiniteAnimation(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}
