import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';

import '../../../../helpers/fixtures.dart';
import '../../../../helpers/responsive_viewport_cases.dart';
import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

/// 含一对 user/assistant 消息的会话 JSON，供窄父约束下气泡内容可达验证。
/// 结构对齐 `history_screen_test_helpers.dart` 的 `_conversation`。
Map<String, dynamic> _seededConversation() => {
  'id': 'conversation-responsive',
  'title': '响应式会话',
  'messageNodes': [
    {
      'id': 'u-1',
      'role': 'user',
      'content': '这是一条较长的用户消息，用来验证窄父约束下气泡正文可达。',
      'parentId': rootConversationParentId,
      'createdAt': DateTime(2026, 5, 5, 10, 0).toIso8601String(),
    },
    {
      'id': 'a-1',
      'role': 'assistant',
      'content': '这是一条较长的助手回复，用来验证窄父约束下气泡正文完整可见。',
      'parentId': 'u-1',
      'createdAt': DateTime(2026, 5, 5, 10, 1).toIso8601String(),
    },
  ],
  'selectedChildByParentId': {rootConversationParentId: 'u-1', 'u-1': 'a-1'},
  'createdAt': DateTime(2026, 5, 5, 10, 0).toIso8601String(),
  'updatedAt': DateTime(2026, 5, 5, 10, 1).toIso8601String(),
  'selectedModelId': null,
  'selectedPresetPromptId': null,
  'reasoningEnabled': false,
  'reasoningEffort': 'medium',
};

/// 点击抽屉遮罩关闭端抽屉（tap 屏幕左上角空白区）。
Future<void> _closeDrawer(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await settleOverlayTransition(tester);
}

void registerChatScreenResponsiveTests() {
  // ChatScreen 只验证两个代表性端点；壳层断点矩阵由 AppShellScaffold 测试负责。
  for (final viewport in [phonePortrait, wideDesktop]) {
    testWidgets('${viewport.name}: 标题/正文/发送入口可达', (tester) async {
      final fakeClient = FakeChatGenerationClient();
      await pumpChatScreen(tester, fakeClient: fakeClient, size: viewport.size);

      expect(find.text('未命名对话'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in [phonePortrait]) {
    testWidgets('${viewport.name}: 抽屉内历史/预设可达，关闭后正文可输入', (tester) async {
      final fakeClient = FakeChatGenerationClient();
      await pumpChatScreen(tester, fakeClient: fakeClient, size: viewport.size);

      await tester.tap(find.byTooltip('打开侧边内容'));
      await settleOverlayTransition(tester);

      expect(find.text('历史会话'), findsOneWidget);
      expect(find.text('预设 Prompt'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _closeDrawer(tester);
      expect(find.text('正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('600: compact composer 摘要与设置 sheet 可达', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(600, 900),
    );

    expect(find.textContaining('更多设置'), findsOneWidget);
    await tester.tap(find.textContaining('更多设置'));
    await settleOverlayTransition(tester);

    expect(find.text('深度思考'), findsOneWidget);
    expect(find.text('自动重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1440: 完整操作区固定顺序与消息过滤可达', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(1440, 900),
    );

    expect(find.text('固定顺序提示词'), findsOneWidget);
    expect(find.text('上下文过滤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('600: seed 消息双方正文可达且无 overflow', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      models: [TestFixtures.gpt41()],
      prompts: [TestFixtures.codeAssistantPrompt()],
      conversations: [_seededConversation()],
    );
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      preferences: preferences,
      database: db,
      size: const Size(600, 900),
    );

    expect(find.textContaining('这是一条较长的用户消息'), findsOneWidget);
    expect(find.textContaining('这是一条较长的助手回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
