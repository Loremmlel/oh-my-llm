import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenBasicsTests() {
  testWidgets('chat screen shows core workspace controls', (tester) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    expect(find.text('模型选择器'), findsNothing);
    expect(find.text('前置 Prompt 选择器'), findsNothing);
    expect(find.text('消息定位条'), findsNothing);
    expect(find.byKey(const ValueKey('message-anchor-rail')), findsNothing);
    expect(find.text('历史会话面板'), findsOneWidget);
    expect(find.text('未命名对话'), findsOneWidget);
    expect(find.textContaining('深度思考：'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(SegmentedButton<ReasoningEffort>), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('思考负担'), findsOneWidget);
  });

  testWidgets('chat screen renames conversation without controller errors', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
    );

    await tester.tap(find.byTooltip('修改对话标题'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '新的对话标题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的对话标题'), findsOneWidget);
  });

  testWidgets('chat screen keeps composer visible on compact layouts', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
      size: const Size(430, 932),
    );

    expect(find.byType(ListView), findsNothing);
    expect(
      find.widgetWithText(FilledButton, '发送').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('chat screen scroll-to-bottom button returns to latest message', (
    tester,
  ) async {
    final preferences = await createSeededPreferences();
    final fakeClient = FakeChatCompletionClient();
    for (var index = 1; index <= 8; index += 1) {
      fakeClient.enqueueChunks(['第 $index 条回复：${'内容 ' * 20}']);
    }

    await pumpChatScreen(
      tester,
      preferences: preferences,
      fakeClient: fakeClient,
      size: const Size(900, 520),
    );

    for (var index = 1; index <= 8; index += 1) {
      await sendMessage(tester, '第 $index 条问题：${'内容 ' * 20}');
      await tester.pumpAndSettle();
    }

    expect(find.byTooltip('滚动到底部'), findsNothing);
    expect(find.textContaining('第 8 条回复'), findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.byTooltip('滚动到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('滚动到底部'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 8 条回复'), findsWidgets);
    expect(find.byTooltip('滚动到底部'), findsNothing);
  });
}
