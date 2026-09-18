import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';

import '../../../helpers/async/widget_test_animation.dart';
import '../../../helpers/fixtures.dart';
import 'chat_screen/chat_screen_test_helpers.dart';

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('打开侧边内容'));
  await settleOverlayTransition(tester);
}

void main() {
  testWidgets('选择与新建会话后关闭抽屉并恢复各会话草稿', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      conversations: [
        TestFixtures.conversation('a', '晨间计划', DateTime(2026, 9, 18)),
        TestFixtures.conversation('b', '夜间笔记', DateTime(2026, 9, 17)),
      ],
    );
    await pumpChatScreen(
      tester,
      fakeClient: FakeChatGenerationClient(),
      database: db,
      preferences: preferences,
    );
    await tester.enterText(chatMessageComposerFinder, '未发送草稿');
    await _openDrawer(tester);
    await tester.tap(find.widgetWithText(ListTile, '夜间笔记'));
    await settleOverlayTransition(tester);
    expect(find.text('夜间笔记 的首条用户消息'), findsOneWidget);
    expect(find.byTooltip('关闭侧栏'), findsNothing);
    await _openDrawer(tester);
    await tester.tap(find.widgetWithText(ListTile, '晨间计划'));
    await settleOverlayTransition(tester);
    expect(find.text('未发送草稿'), findsOneWidget);
    await _openDrawer(tester);
    await tester.tap(find.widgetWithText(TextButton, '新建对话'));
    await settleOverlayTransition(tester);
    expect(find.byTooltip('关闭侧栏'), findsNothing);
    expect(find.text('未命名对话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预设调整保持抽屉打开且重开后恢复分段和滚动内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      prompts: [
        TestFixtures.presetPrompt(
          id: 'writing',
          name: '写作规则',
          messages: [
            for (var i = 0; i < 30; i++)
              TestFixtures.promptMessage(id: 'rule-$i', title: '写作规则条目 $i'),
          ],
        ),
      ],
    );
    await pumpChatScreen(
      tester,
      fakeClient: FakeChatGenerationClient(),
      database: db,
      preferences: preferences,
      size: const Size(390, 844),
    );
    await _openDrawer(tester);
    await tester.tap(find.text('预设'));
    await tester.pump();
    await tester.tap(
      find.byType(DropdownButtonFormField<String>).hitTestable(),
    );
    await settleOverlayTransition(tester);
    await tester.tap(find.text('写作规则').last);
    await settleOverlayTransition(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(activeChatConversationProvider).selectedPresetPromptId,
      'writing',
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(
      container.read(presetPromptsProvider).single.messages.first.enabled,
      isFalse,
    );
    expect(find.byTooltip('关闭侧栏'), findsOneWidget);
    final target = find.text('写作规则条目 20');
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(find.text('历史会话'));
    await tester.pump();
    await tester.tap(find.text('预设'));
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('关闭侧栏'));
    await settleOverlayTransition(tester);
    await _openDrawer(tester);
    expect(target.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('生成中浏览历史不会切换会话或关闭抽屉', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      models: [TestFixtures.gpt41()],
      conversations: [
        TestFixtures.conversation('saved', '已存会话', DateTime(2026, 9, 17)),
      ],
    );
    final fake = FakeChatGenerationClient();
    final stream = fake.enqueueControlledStream();
    await pumpChatScreen(
      tester,
      fakeClient: fake,
      database: db,
      preferences: preferences,
    );
    await tester.tap(find.byTooltip('新建对话'));
    await tester.pump();
    await sendMessage(tester, '继续写作');
    await stream.listened;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final activeId = container.read(activeConversationIdProvider);
    await tester.tap(find.byTooltip('打开侧边内容'));
    final savedConversation = find.widgetWithText(ListTile, '已存会话');
    // 流式进度持续动画，以历史条目实际可点击作为等待完成条件。
    const animationStep = Duration(milliseconds: 100);
    for (
      var frame = 0;
      frame < 20 && savedConversation.hitTestable().evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(animationStep);
    }
    expect(savedConversation.hitTestable(), findsOneWidget);
    await tester.tap(savedConversation);
    await tester.pump();
    expect(container.read(activeConversationIdProvider), activeId);
    expect(find.byTooltip('关闭侧栏'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '新建对话'));
    await tester.pump();
    expect(container.read(activeConversationIdProvider), activeId);
    stream.add(TestFixtures.contentChunk('已完成'));
    await stream.close();
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '等待受控回复结束',
    );
    expect(tester.takeException(), isNull);
  });
}
