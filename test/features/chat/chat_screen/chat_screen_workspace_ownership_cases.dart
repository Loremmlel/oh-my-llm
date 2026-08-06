import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/settings/application/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

import 'chat_screen_test_helpers.dart';

/// composer 输入框的公开 test-key（`sendMessage` 等既有 helper 已复用）。
final _composerFinder = find.byKey(const ValueKey('chat-message-composer'));

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerFinder).controller!.text;

/// 点击指定消息气泡（按消息 id 定位）的「编辑消息」按钮。
///
/// 消息列表经 ScrollablePositionedList 渲染，其元素树遍历顺序与显示顺序相反，
/// 不能依赖 `find.byTooltip('编辑消息').last` 命中最新消息；用消息 id 的
/// KeyedSubtree 定位气泡后取其后代编辑按钮，与列表顺序解耦。
Future<void> _tapEditMessage(WidgetTester tester, String messageId) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(ValueKey<String>(messageId)),
      matching: find.byTooltip('编辑消息'),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

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

  testWidgets('编辑带模板消息变量随提交生效；编辑无模板消息不显示会话模板输入', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['普通回复'])
      ..enqueueChunks(['普通消息修改回复'])
      ..enqueueChunks(['模板回复'])
      ..enqueueChunks(['编辑后模板回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;

    // 注册一个带非空默认值的模板变量，便于区分「模板默认值」与「用户输入」。
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

    // ── 路径 B：编辑无模板消息，但会话级 draft 已选中模板 ──
    await sendMessage(tester, '普通消息');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    final plainMessageId = container
        .read(activeChatConversationProvider)
        .messages
        .lastWhere((m) => m.role == ChatMessageRole.user)
        .id;

    // 会话级 draft 选中模板（模拟「session draft 有模板」）。
    await _selectTemplate(tester, '变量模板');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 编辑无模板消息：不显示会话模板的变量输入框（修复前这里会显示并静默丢弃）。
    await _tapEditMessage(tester, plainMessageId);
    expect(find.byKey(const ValueKey('template-variable-title')), findsNothing);

    // 提交编辑：发送纯正文，分支不带模板，会话级模板选择保留。
    await tester.enterText(_composerFinder, '普通消息修改');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    final afterPlainEdit = container.read(activeChatConversationProvider);
    final plainBranch = afterPlainEdit.messageNodes.firstWhere((m) {
      return m.role == ChatMessageRole.user && m.content == '普通消息修改';
    });
    expect(plainBranch.templatePromptId, isNull);
    expect(plainBranch.templateVariableValues, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(convId)
          .selectedTemplatePromptId,
      'tp-var',
    );

    // ── 路径 A：编辑带模板的消息，修改变量后提交 ──
    await tester.enterText(_composerFinder, '模板问题');
    await tester.pump();
    final titleField = find.byKey(const ValueKey('template-variable-title'));
    await tester.enterText(titleField, '甲');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 发送后：会话级 draft body 清空、模板变量保留 '甲'。
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(convId)
          .templateVariableValuesByTemplateId['tp-var']?['title'],
      '甲',
    );

    // 编辑该带模板消息：变量输入框携带已保存值，改为 '乙' 后提交。
    final templatedMessageId = container
        .read(activeChatConversationProvider)
        .messages
        .lastWhere(
          (m) =>
              m.role == ChatMessageRole.user && m.templatePromptId == 'tp-var',
        )
        .id;
    await _tapEditMessage(tester, templatedMessageId);
    expect(tester.widget<TextField>(titleField).controller!.text, '甲');
    await tester.enterText(titleField, '乙');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 新分支携带 '乙' 与模板 id；会话级 draft 变量仍为 '甲'（编辑未污染）。
    final afterTemplatedEdit = container.read(activeChatConversationProvider);
    final templatedBranch = afterTemplatedEdit.messageNodes.firstWhere((m) {
      return m.role == ChatMessageRole.user &&
          m.templateVariableValues['title'] == '乙';
    });
    expect(templatedBranch.templatePromptId, 'tp-var');
    expect(templatedBranch.templateVariableValues['title'], '乙');
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(convId)
          .templateVariableValuesByTemplateId['tp-var']?['title'],
      '甲',
    );
  });
}
