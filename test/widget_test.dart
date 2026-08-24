import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
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
          customHeadersMapProvider.overrideWith((ref) => const {}),
          // 固定 Windows 宿主：flutter_test 默认平台是 Android，会绑定真实
          // MethodChannel adapter 并残留命令超时 Timer；与 test harness 约定一致。
          // 通知平台件用 no-op 记录（harness 同一约定）：本测试不验证通知，
          // 且真实 Windows host client 与 Android bridge 一样带命令超时
          // Timer，绑定会在测试结束时残留 pending Timer。
          ...appCompositionOverrides(
            hostPlatform: TargetPlatform.windows,
            notificationPlatformBindingsFactory:
                createOtherPlatformChatGenerationNotificationBindings,
          ),
        ],
        child: const OhMyLlmApp(),
      ),
    );

    await tester.pump();

    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
  });
}
