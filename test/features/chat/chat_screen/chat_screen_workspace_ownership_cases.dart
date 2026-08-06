import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';

import 'chat_screen_test_helpers.dart';

/// composer 输入框的公开 test-key（`sendMessage` 等既有 helper 已复用）。
final _composerFinder = find.byKey(const ValueKey('chat-message-composer'));

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerFinder).controller!.text;

void registerChatScreenWorkspaceOwnershipTests() {
  testWidgets('A→B 首次切换 B 不显示 A 的正文，切回 A 恢复 A 的正文', (tester) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convAId = container.read(chatSessionsProvider).activeConversation.id;

    // 先让 A 有一条消息，否则「新建对话」因当前会话无消息而空操作。
    await sendMessage(tester, '第一条问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    const draftA = 'A 的正文';
    await tester.enterText(_composerFinder, draftA);
    await tester.pump();

    // 新建会话 B：B 的输入框不应继承 A 的正文草稿。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(_composerText(tester), isEmpty);

    // 切回 A：A 的正文草稿应恢复。
    container.read(chatSessionsProvider.notifier).selectConversation(convAId);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(_composerText(tester), draftA);
  });

  testWidgets('ChatScreen 卸载后在同 scope 重挂，body 草稿恢复', (tester) async {
    final fakeClient = FakeChatCompletionClient();
    final mount = await pumpChatScreenScope(tester, fakeClient: fakeClient);
    await tester.pumpWidget(mount.scope);
    await tester.pump();

    const draft = '未发送草稿';
    await tester.enterText(_composerFinder, draft);
    await tester.pump();

    // 卸载 ChatScreen（ProviderScope 保持存活）。
    mount.showChat.value = false;
    await tester.pump();
    // 重挂进同一 scope。
    mount.showChat.value = true;
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(_composerText(tester), draft);
  });
}
