import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

import 'helpers/fixtures.dart';

void main() {
  testWidgets('app bootstrap smoke test', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [TestFixtures.gpt41()],
      prompts: [TestFixtures.codeAssistantPrompt()],
    );

    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const OhMyLlmApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
  });
}
