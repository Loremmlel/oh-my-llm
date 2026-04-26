import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

void main() {
  testWidgets('app boots into chat placeholder route', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const OhMyLlmApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('对话页'), findsOneWidget);
    expect(find.text('Oh My LLM'), findsOneWidget);
  });
}
