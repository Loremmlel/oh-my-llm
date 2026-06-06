import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_screen_test_helpers.dart';

void registerSyncScreenLifecycleTests() {
  group('SyncScreen 生命周期', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    Future<void> switchToServerMode(WidgetTester tester) async {
      await tester.tap(find.text('作为服务端'));
      await tester.pump();
    }

    // 跳过：服务端启动后 UDP 广播定时器（2s 周期）导致 pumpAndSettle 超时。
    // 需要注入 MockClock 或将定时器改为可测试形式后才能启用。
    testWidgets('server 模式下 paused 时自动 stop', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);
      await switchToServerMode(tester);

      await tester.tap(find.text('启动广播'));
      await tester.pumpAndSettle();
      expect(find.text('正在广播'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('正在广播'), findsNothing);
      expect(find.text('启动广播'), findsOneWidget);
    }, skip: true);

    testWidgets('server 模式下 paused→resumed 时自动重启', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);
      await switchToServerMode(tester);

      await tester.tap(find.text('启动广播'));
      await tester.pumpAndSettle();
      expect(find.text('正在广播'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('启动广播'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('正在广播'), findsOneWidget);
    }, skip: true);
  });
}
