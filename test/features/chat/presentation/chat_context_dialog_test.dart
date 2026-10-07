import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_context_dialog.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/async/widget_test_animation.dart';
import 'chat_screen/chat_screen_test_helpers.dart';

void main() {
  testWidgets('生成时查看已准备的请求，流式正文不会混入快照且 Escape 可关闭', (tester) async {
    final client = FakeChatGenerationClient();
    final stream = client.enqueueControlledStream();
    await pumpChatScreen(tester, fakeClient: client);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await sendMessage(tester, '快照输入');
    await stream.listened;
    await tester.tap(find.byTooltip('查看当前上下文'));
    await tester.pump();
    final animation = ModalRoute.of(
      tester.element(find.byType(ChatContextDialog)),
    )!.animation!;
    await settleStreamingOverlayTransition(
      tester,
      animation,
      AnimationStatus.completed,
    );
    expect(find.text('本次请求 · 已准备'), findsOneWidget);
    stream.add(const ChatGenerationChunk(contentDelta: '新生成的正文'));
    await tester.pump();
    final view = find.byType(ChatContextDialog);
    expect(
      find.descendant(of: view, matching: find.text('快照输入')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: view, matching: find.textContaining('新生成的正文')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleStreamingOverlayTransition(
      tester,
      animation,
      AnimationStatus.dismissed,
    );
    expect(find.text('本次请求 · 已准备'), findsNothing);
    await stream.close();
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase.isTerminal ?? false,
      description: '快照用例生成完成',
    );
  });

  testWidgets('手机从更多查看草稿展开上下文，复制和返回不影响发送内容', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preset = TestFixtures.presetPrompt(
      id: 'macro',
      name: '写作规则',
      messages: [
        TestFixtures.promptMessage(id: 'before', content: '{{setvar::x::简洁}}'),
        TestFixtures.promptMessage(
          id: 'after',
          title: '强调',
          content: '{{getvar::x}}：{{lastUserMessage}}',
          placement: PromptMessagePlacement.after,
        ),
      ],
    ).copyWith(syntax: PresetPromptSyntax.sillyTavernSubsetV1);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      models: [TestFixtures.gpt41()],
      prompts: [preset],
    );
    final client = FakeChatGenerationClient();
    client.enqueueChunks(['回复']);
    await pumpChatScreen(
      tester,
      database: db,
      preferences: preferences,
      fakeClient: client,
      size: const Size(390, 844),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    container
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(selectedPresetPromptId: preset.id);
    await tester.pump();
    await tester.enterText(chatMessageComposerFinder, '继续写作');
    await tester.tap(find.byTooltip('更多对话操作'));
    await settleOverlayTransition(tester);
    await tester.tap(find.text('查看当前上下文'));
    await settleOverlayTransition(tester);
    expect(find.text('请求预览 · 包含未发送草稿'), findsOneWidget);
    expect(find.text('简洁：继续写作'), findsOneWidget);
    expect(client.requestHistory, isEmpty);
    final copied = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.complete((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.text('复制全部文本'));
    expect(await copied.future, contains('简洁：继续写作'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回对话'));
    await settleOverlayTransition(tester);
    expect(find.text('继续写作'), findsOneWidget);
    await sendMessage(tester, '继续写作');
    await waitForChatGeneration(
      tester,
      container,
      (state) => state.generation?.phase.isTerminal ?? false,
      description: '草稿发送完成',
    );
    expect(client.lastRequest!.messages.map((m) => m.content), [
      '继续写作',
      '简洁：继续写作',
    ]);
    expect(find.byType(ChatContextDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
