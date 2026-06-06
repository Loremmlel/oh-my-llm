import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_screen_test_helpers.dart';

void registerSyncScreenRenderTests() {
  group('SyncScreen 渲染', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    testWidgets('渲染标题、标签页和连接模式选择器', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      expect(find.text('局域网同步'), findsOneWidget);
      expect(find.text('连接'), findsWidgets);
      expect(find.text('同步'), findsWidgets);
      expect(find.text('作为客户端'), findsOneWidget);
      expect(find.text('作为服务端'), findsOneWidget);
    });

    testWidgets('默认显示连接标签页', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      expect(find.text('发现服务端'), findsWidgets);
      expect(find.text('服务端广播'), findsNothing);
    });

    testWidgets('切换到服务端模式显示服务端面板', (tester) async {
      await pumpSyncScreen(tester, preferences: preferences);

      await tester.tap(find.text('作为服务端'));
      await tester.pump();

      expect(find.text('服务端广播'), findsOneWidget);
      expect(find.text('发现服务端'), findsNothing);
    });
  });
}
