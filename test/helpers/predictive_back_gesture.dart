import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 从 Android 系统通道驱动真实路由的预测性返回。
Future<void> sendPredictiveBackEvent(
  WidgetTester tester,
  String method, {
  double progress = 0,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, {
        'touchOffset': <double>[5 + 300 * progress, 300],
        'progress': progress,
        'swipeEdge': 0,
      }),
    ),
    (_) {},
  );
}
