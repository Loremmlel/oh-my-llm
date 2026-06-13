import 'package:flutter_test/flutter_test.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenTabNavigationTests() {
  testWidgets('settings screen shows tab bar with five tabs', (tester) async {
    await setUpSettingsScreen(tester);

    expect(find.text('服务商'), findsOneWidget);
    expect(find.text('预设'), findsOneWidget);
    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('其它'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
  });

  testWidgets('settings screen starts on persisted tab index', (tester) async {
    await setUpSettingsScreen(tester, initialTabIndex: 2);

    expect(find.text('记忆总结提示词'), findsOneWidget);
    expect(find.text('模板提示词'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);
  });

  testWidgets('switching tabs updates the visible content', (tester) async {
    await setUpSettingsScreen(tester);

    expect(find.text('服务商设置'), findsOneWidget);

    await switchToTab(tester, 1);
    expect(find.text('预设 Prompt'), findsOneWidget);

    await switchToTab(tester, 2);
    expect(find.text('记忆总结提示词'), findsOneWidget);

    await switchToTab(tester, 3);
    expect(find.text('自动重试'), findsOneWidget);

    await switchToTab(tester, 4);
    expect(find.text('请求头定义'), findsOneWidget);

    await switchToTab(tester, 0);
    expect(find.text('服务商设置'), findsOneWidget);
  });
}
