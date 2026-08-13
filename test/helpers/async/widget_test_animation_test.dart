import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_animation.dart';

void main() {
  testWidgets('有限动画完成后 helper 返回', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 120),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, child) => const Text('内容'),
        ),
      ),
    );
    controller.forward();
    await settleAnimatedWidgetTransition(tester);
    expect(controller.status, AnimationStatus.completed);
  });

  testWidgets('无限动画触发超时保护', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 500),
    )..repeat();
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, child) => const Text('内容'),
        ),
      ),
    );
    // 直接传已启动的 settle future 会在 expectLater 的 guardSync
    // 处触发"守卫函数冲突"，改为传闭包让 matcher 内部再启动。
    await expectLater(
      () => settleAnimatedWidgetTransition(tester),
      throwsA(isA<FlutterError>()),
    );
    // vsync: tester 的 ticker 不随 widget 树销毁，重复动画的 controller
    // 必须在用例体内 dispose；addTearDown 执行晚于 ticker 泄漏检查。
    controller.dispose();
  });
}
