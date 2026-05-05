import 'package:flutter_test/flutter_test.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenDefaultsTests() {
  testWidgets('settings screen no longer shows chat defaults section', (
    tester,
  ) async {
    final preferences = await createDefaultsSeededPreferences();

    await pumpSettingsScreen(tester, preferences: preferences);

    expect(find.text('聊天默认项'), findsNothing);
    expect(find.text('模型设置'), findsOneWidget);
    expect(find.text('前置 Prompt 设置'), findsOneWidget);
    expect(find.textContaining('聊天页会记住最近一次使用的模型'), findsOneWidget);
    expect(find.textContaining('聊天页会记住最近一次使用的选择'), findsOneWidget);
  });
}
