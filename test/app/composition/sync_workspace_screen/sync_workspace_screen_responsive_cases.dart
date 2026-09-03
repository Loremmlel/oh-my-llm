import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import 'sync_workspace_screen_test_helpers.dart';

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void registerSyncScreenResponsiveTests() {
  for (final viewport in [shellBelowBoundary, shellAtBoundary]) {
    testWidgets('${viewport.name}: 同步页切换壳层导航模式', (tester) async {
      final preferences = await _freshPrefs();
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        size: viewport.size,
      );

      expect(find.text('局域网同步'), findsOneWidget);
      if (viewport.shellMode == ShellNavigationMode.bottomBar) {
        expect(find.byType(NavigationBar), findsOneWidget);
      } else {
        expect(find.byType(NavigationRail), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
