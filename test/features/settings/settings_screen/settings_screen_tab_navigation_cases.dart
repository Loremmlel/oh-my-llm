import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenTabNavigationTests() {
  testWidgets('settings screen shows tab bar with four tabs', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(tester, preferences: preferences, database: database);

    expect(find.text('服务商'), findsOneWidget);
    expect(find.text('预设'), findsOneWidget);
    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('其它'), findsOneWidget);
  });

  testWidgets('settings screen starts on persisted tab index', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(tester, preferences: preferences, database: database, initialTabIndex: 2);

    expect(find.text('记忆总结提示词'), findsOneWidget);
    expect(find.text('模板提示词'), findsOneWidget);
    expect(find.text('固定顺序提示词'), findsOneWidget);
  });

  testWidgets('switching tabs updates the visible content', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await createEmptyPreferences(database);
    await pumpSettingsScreen(tester, preferences: preferences, database: database);

    expect(find.text('服务商设置'), findsOneWidget);

    await switchToTab(tester, 1);
    expect(find.text('预设 Prompt'), findsOneWidget);

    await switchToTab(tester, 2);
    expect(find.text('记忆总结提示词'), findsOneWidget);

    await switchToTab(tester, 3);
    expect(find.text('自动重试'), findsOneWidget);

    await switchToTab(tester, 0);
    expect(find.text('服务商设置'), findsOneWidget);
  });
}
