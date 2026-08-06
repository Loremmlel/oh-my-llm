import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import 'chat_screen_test_helpers.dart';

/// composer 输入框的公开 test-key（`sendMessage` 等既有 helper 已复用）。
final _composerFinder = find.byKey(const ValueKey('chat-message-composer'));

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerFinder).controller!.text;

/// 通过模板下拉选择指定名称的模板（沿用既有 cases 的 dropdown finder 手法）。
Future<void> _selectTemplate(WidgetTester tester, String title) async {
  await tester.tap(
    find.ancestor(
      of: find.text('模板提示词'),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

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

  testWidgets('跨会话同名模板变量：B 无值时显示模板默认值而非 A 的值', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['A 回复'])
      ..enqueueChunks(['B 回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convAId = container.read(chatSessionsProvider).activeConversation.id;

    // 先让 A 有一条消息，否则「新建对话」因当前会话无消息而空操作。
    await sendMessage(tester, 'A 的问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 注册一个带非空默认值的模板变量，便于区分「模板默认值」与「无值」。
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-var',
            title: '变量模板',
            content: '请按{{title}}输出。',
            variables: const [
              TemplatePromptVariable(name: 'title', defaultValue: '默认标题'),
            ],
            updatedAt: DateTime(2026, 5, 5, 0, 1),
          ),
        );
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    final titleField = find.byKey(const ValueKey('template-variable-title'));

    // A 选择模板并输入 title='甲'。
    await _selectTemplate(tester, '变量模板');
    await tester.enterText(titleField, '甲');
    await tester.pump();

    // 新建 B 并选择同一模板（不输入任何值）。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    final convBId = container.read(chatSessionsProvider).activeConversation.id;
    await _selectTemplate(tester, '变量模板');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 让 B 也有一条消息，否则 B 不在历史摘要里、selectConversation(B) 空操作。
    await sendMessage(tester, 'B 的问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 切 A→B→A→B：B 的 title 字段应回落模板默认值，而非残留 A 的 '甲'。
    container.read(chatSessionsProvider.notifier).selectConversation(convAId);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    container.read(chatSessionsProvider.notifier).selectConversation(convBId);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(tester.widget<TextField>(titleField).controller!.text, '默认标题');
  });

  testWidgets('编辑取消恢复编辑前草稿，不污染会话级 draft', (tester) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;

    // 先发一条消息，让用户消息气泡提供「编辑消息」入口。
    await sendMessage(tester, '第一条问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 发送 accepted 会清空 body，随后输入普通草稿进入会话级 draft。
    await tester.enterText(_composerFinder, '普通草稿');
    await tester.pump();

    // 进入编辑模式：composer 显示消息正文。
    await tester.tap(find.byTooltip('编辑消息').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 编辑中修改正文（只写页面草稿，不写会话级 draft）。
    await tester.enterText(_composerFinder, '编辑中的修改');
    await tester.pump();

    // 取消编辑：恢复编辑前草稿，会话级 draft 保持原值。
    await tester.tap(find.byTooltip('取消编辑'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(_composerText(tester), '普通草稿');
    expect(
      container.read(composerDraftProvider.notifier).draftFor(convId).body,
      '普通草稿',
    );
  });

  testWidgets('编辑后切换会话不污染旧会话草稿', (tester) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convAId = container.read(chatSessionsProvider).activeConversation.id;

    await sendMessage(tester, 'A 的问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    await tester.enterText(_composerFinder, 'A 草稿');
    await tester.pump();

    await tester.tap(find.byTooltip('编辑消息').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    await tester.enterText(_composerFinder, '编辑修改');
    await tester.pump();

    // 编辑中切换会话：编辑事务被丢弃，旧会话草稿保持原值。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    final convBId = container.read(chatSessionsProvider).activeConversation.id;
    expect(convBId, isNot(convAId));

    // 切回 A：恢复 A 的原草稿，而非编辑中的修改。
    container.read(chatSessionsProvider.notifier).selectConversation(convAId);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(_composerText(tester), 'A 草稿');
    expect(
      container.read(composerDraftProvider.notifier).draftFor(convAId).body,
      'A 草稿',
    );
  });

  testWidgets('编辑后卸载重挂丢弃编辑模式，草稿恢复为会话级值', (tester) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);
    final mount = await pumpChatScreenScope(tester, fakeClient: fakeClient);
    await tester.pumpWidget(mount.scope);
    await tester.pump();

    await sendMessage(tester, 'A 的问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    await tester.enterText(_composerFinder, 'A 草稿');
    await tester.pump();

    await tester.tap(find.byTooltip('编辑消息').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    await tester.enterText(_composerFinder, '编辑修改');
    await tester.pump();

    // 卸载并重挂 ChatScreen：编辑事务随页面销毁丢弃，草稿恢复为会话级值。
    mount.showChat.value = false;
    await tester.pump();
    mount.showChat.value = true;
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.byTooltip('取消编辑'), findsNothing);
    expect(_composerText(tester), 'A 草稿');
  });

  testWidgets('编辑空正文发送被拒：保留输入与编辑态', (tester) async {
    final fakeClient = FakeChatCompletionClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);

    await sendMessage(tester, '第一条问题');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    await tester.tap(find.byTooltip('编辑消息').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 编辑中清空正文 → 发送被 empty 拒绝，编辑态与输入保留。
    await tester.enterText(_composerFinder, '   ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.byTooltip('取消编辑'), findsOneWidget);
    expect(_composerText(tester), '   ');
    // 空正文被拒，不新增请求（仅保留初始 sendMessage 的那一次）。
    expect(fakeClient.requestHistory, hasLength(1));
  });
}
