import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenDefaultsTests() {
  testWidgets('settings screen persists chat defaults', (tester) async {
    final preferences = await createDefaultsSeededPreferences();

    await pumpSettingsScreen(tester, preferences: preferences);

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Sonnet').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('代码助手').last);
    await tester.pumpAndSettle();

    expect(jsonDecode(preferences.getString(chatDefaultsStorageKey)!), {
      'defaultModelId': 'model-2',
      'defaultPromptTemplateId': 'prompt-1',
    });
  });
}
