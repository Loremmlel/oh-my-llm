import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';
import '../../../helpers/async/widget_test_animation.dart';

void main() {
  testWidgets('删除服务商需确认影响范围，取消保留模型，确认后删除', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [
        TestFixtures.model(displayName: '写作模型', providerName: '写作服务商'),
        TestFixtures.model(
          id: 'model-2',
          displayName: '审稿模型',
          providerName: '写作服务商',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      child: const SettingsScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await container
        .read(chatDefaultsProvider.notifier)
        .rememberModelId('model-2');

    await tester.tap(find.byTooltip('服务商操作'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('删除服务商'));
    await settleOverlayTransition(tester);
    expect(find.text('将删除“写作服务商”及其 2 个模型。聊天记录会保留。'), findsOneWidget);
    expect(
      container.read(llmProviderConfigsProvider).single.models,
      hasLength(2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleOverlayTransition(tester);
    expect(container.read(llmProviderConfigsProvider), hasLength(1));
    expect(container.read(chatDefaultsProvider).defaultModelId, 'model-2');

    await tester.tap(find.byTooltip('服务商操作'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('删除服务商'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除服务商'));
    await settleOverlayTransition(tester);
    expect(container.read(llmProviderConfigsProvider), isEmpty);
    expect(container.read(chatDefaultsProvider).defaultModelId, isNull);
  });

  testWidgets('删除模型取消保留原配置，确认只删除目标模型并清除选择记忆', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final preferences = await TestFixtures.seedPreferences(
      database: database,
      models: [
        TestFixtures.model(displayName: '写作模型', providerName: '写作服务商'),
        TestFixtures.model(
          id: 'model-2',
          displayName: '审稿模型',
          providerName: '写作服务商',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      preferences: preferences,
      database: database,
      child: const SettingsScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await container
        .read(chatDefaultsProvider.notifier)
        .rememberModelId('model-1');
    await tester.tap(find.text('展开模型（2）'));
    await tester.pump();
    await tester.tap(find.byTooltip('模型操作').first);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('删除模型'));
    await settleOverlayTransition(tester);
    expect(find.text('将从“写作服务商”删除模型“写作模型”。聊天记录会保留。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleOverlayTransition(tester);
    expect(
      container.read(llmProviderConfigsProvider).single.models,
      hasLength(2),
    );
    expect(container.read(chatDefaultsProvider).defaultModelId, 'model-1');
    await tester.tap(find.byTooltip('模型操作').first);
    await settleOverlayTransition(tester);
    await tester.tap(find.text('删除模型'));
    await settleOverlayTransition(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除模型'));
    await settleOverlayTransition(tester);
    expect(
      container.read(llmProviderConfigsProvider).single.models.single.id,
      'model-2',
    );
    expect(container.read(chatDefaultsProvider).defaultModelId, isNull);
    expect(tester.takeException(), isNull);
  });
}
