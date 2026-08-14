import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/android_video_system_ui_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('进入尚未完成时恢复会等待进入结束再执行', (tester) async {
    final calls = <MethodCall>[];
    final firstCall = Completer<void>();
    final firstCallObserved = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          if (calls.length == 1) {
            firstCallObserved.complete();
            await firstCall.future;
          }
          return null;
        });
    final controller = AndroidVideoSystemUiController();

    final enter = controller.enter();
    await firstCallObserved.future;
    final restore = controller.restore();
    await tester.pump();

    expect(calls, hasLength(1));

    firstCall.complete();
    await enter;
    await restore;
    expect(calls, hasLength(4));
  });

  testWidgets('恢复中途失败后再次恢复会重新执行平台调用', (tester) async {
    final calls = <MethodCall>[];
    var failFirstRestoreCall = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          if (calls.length == 3 && failFirstRestoreCall) {
            failFirstRestoreCall = false;
            throw PlatformException(code: 'restore-failed');
          }
          return null;
        });
    final controller = AndroidVideoSystemUiController();
    await controller.enter();

    await expectLater(controller.restore(), throwsA(isA<PlatformException>()));
    final callsAfterFailure = calls.length;
    await controller.restore();

    expect(callsAfterFailure, 3);
    expect(calls.length, greaterThan(callsAfterFailure));
  });

  testWidgets('进入第二步失败且即时补偿也失败时退出仍恢复方向', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          if (calls.length == 2 || calls.length == 3) {
            throw PlatformException(code: 'platform-failed');
          }
          return null;
        });
    final controller = AndroidVideoSystemUiController();

    await expectLater(controller.enter(), throwsA(isA<PlatformException>()));
    await controller.restore();

    expect(calls.map((call) => call.method), [
      'SystemChrome.setPreferredOrientations',
      'SystemChrome.setEnabledSystemUIMode',
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setEnabledSystemUIOverlays',
      'SystemChrome.setPreferredOrientations',
    ]);
  });
}
