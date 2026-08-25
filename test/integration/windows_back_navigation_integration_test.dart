import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../helpers/async/widget_test_animation.dart';
import '../helpers/fixtures.dart';

/// 集成测试：Windows 返回输入（鼠标后退侧键）的根部组合端到端证明——
/// 真实 [OhMyLlmApp] 全栈下 Windows 宿主挂载 adapter 并驱动既有返回链，
/// Android 宿主不挂载、输入不产生任何导航。
Future<void> _pumpFullApp(WidgetTester tester) async {
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
        customHeadersMapProvider.overrideWith((ref) => const {}),
        ...appCompositionOverrides(hostPlatform: TargetPlatform.windows),
      ],
      child: const OhMyLlmApp(),
    ),
  );
  await tester.pump();
}

void main() {
  group('根部组合（真实 OhMyLlmApp）', () {
    testWidgets(
      'Windows 宿主鼠标后退侧键把设置页退回对话',
      (tester) async {
        await _pumpFullApp(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('设置'),
          ),
        );
        await settleRouteTransition(tester);
        expect(find.text('服务商设置'), findsOneWidget);

        await tester.tapAt(
          tester.getCenter(find.byType(SettingsScreen)),
          buttons: kBackMouseButton,
        );
        await settleRouteTransition(tester);

        expect(find.text('服务商设置'), findsNothing);
        expect(find.text('历史会话面板'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Android 宿主鼠标后退侧键不触发返回',
      (tester) async {
        await _pumpFullApp(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('设置'),
          ),
        );
        await settleRouteTransition(tester);
        expect(find.text('服务商设置'), findsOneWidget);

        await tester.tapAt(
          tester.getCenter(find.byType(SettingsScreen)),
          buttons: kBackMouseButton,
        );
        await settleRouteTransition(tester);

        // Android 不挂载 Windows adapter：侧键输入不产生任何导航。
        expect(find.text('服务商设置'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
