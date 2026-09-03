import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';
import 'package:oh_my_llm/features/settings/application/prompts/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

/// composer 输入框：与 helpers 的 sendMessage 共用同一可见 label 定位，
/// 不依赖内部 test-key。
final _composerFinder = chatMessageComposerFinder;

void _expectFieldText(Finder field, String text) {
  expect(find.descendant(of: field, matching: find.text(text)), findsWidgets);
}

/// 模板变量区域的变量输入框：按变量名 label 定位并限定在变量区域内，
/// 避免与页面其他同名文本（如会话标题）混淆。
Finder _variableField(String name) => find.widgetWithText(TextField, name);

/// 点击指定消息气泡（按完整可见用户消息正文定位）的「编辑消息」按钮。
///
/// 消息列表经 ScrollablePositionedList 渲染，其元素树遍历顺序与显示顺序相反，
/// 不能依赖 `find.byTooltip('编辑消息').last` 命中最新消息；用完整可见正文
/// 定位气泡（会话内唯一）后取其后代编辑按钮，与列表顺序解耦。
Future<void> _tapEditMessage(WidgetTester tester, String messageContent) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ChatMessageBubble, messageContent),
      matching: find.byTooltip('编辑消息'),
    ),
  );
  // 进入编辑模式伴随 composer 布局过渡，按组件动画等待。
  await settleAnimatedWidgetTransition(tester);
}

/// 通过模板下拉选择指定名称的模板（沿用既有 cases 的 dropdown finder 手法）。
Future<void> _selectTemplate(WidgetTester tester, String title) async {
  await tester.tap(
    find.ancestor(
      of: find.text('模板提示词'),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    ),
  );
  // 下拉菜单开合属 overlay 过渡。
  await settleOverlayTransition(tester);
  await tester.tap(find.text(title).last);
  await settleOverlayTransition(tester);
}

/// 注册「变量模板」（tp-var，变量 title 默认值「默认标题」）并等待渲染。
Future<void> _seedVariableTemplate(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
  // upsert 是同步持久化，单帧渲染即可。
  await tester.pump();
}

void registerChatScreenWorkspaceOwnershipTests() {
  testWidgets('A→B 首次切换 B 不显示 A 的正文，切回 A 恢复 A 的正文', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convAId = container.read(chatSessionsProvider).activeConversation.id;

    // 先让 A 有一条消息，否则「新建对话」因当前会话无消息而空操作。
    await sendMessage(tester, '第一条问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: 'A 首条消息生成完成',
    );

    const draftA = 'A 的正文';
    await tester.enterText(_composerFinder, draftA);
    await tester.pump();

    // 新建会话 B：B 的输入框不应继承 A 的正文草稿。会话切换是同步状态变更。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pump();
    expect(
      find.descendant(of: _composerFinder, matching: find.text(draftA)),
      findsNothing,
    );

    // 切回 A：A 的正文草稿应恢复。
    container.read(chatSessionsProvider.notifier).selectConversation(convAId);
    await tester.pump();
    _expectFieldText(_composerFinder, draftA);
  });

  testWidgets('编辑取消恢复编辑前草稿，不污染会话级 draft', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;

    // 先发一条消息，让用户消息气泡提供「编辑消息」入口。
    await sendMessage(tester, '第一条问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '取消编辑用例生成完成',
    );

    // 发送 accepted 会清空 body，随后输入普通草稿进入会话级 draft。
    await tester.enterText(_composerFinder, '普通草稿');
    await tester.pump();

    // 进入编辑模式：composer 显示消息正文。
    await tester.tap(find.byTooltip('编辑消息').last);
    await settleAnimatedWidgetTransition(tester);

    // 编辑中修改正文（只写页面草稿，不写会话级 draft）。
    await tester.enterText(_composerFinder, '编辑中的修改');
    await tester.pump();

    // 取消编辑：恢复编辑前草稿，会话级 draft 保持原值。
    await tester.tap(find.byTooltip('取消编辑'));
    await settleAnimatedWidgetTransition(tester);

    _expectFieldText(_composerFinder, '普通草稿');
    expect(
      container.read(composerDraftProvider.notifier).draftFor(convId).body,
      '普通草稿',
    );
  });

  testWidgets('编辑后卸载重挂丢弃编辑模式，草稿恢复为会话级值', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    final mount = await pumpChatScreenScope(tester, fakeClient: fakeClient);
    await tester.pumpWidget(mount.scope);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );

    await sendMessage(tester, 'A 的问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '重挂用例 A 问题生成完成',
    );

    await tester.enterText(_composerFinder, 'A 草稿');
    await tester.pump();

    await tester.tap(find.byTooltip('编辑消息').last);
    await settleAnimatedWidgetTransition(tester);
    await tester.enterText(_composerFinder, '编辑修改');
    await tester.pump();

    // 卸载并重挂 ChatScreen：编辑事务随页面销毁丢弃，草稿恢复为会话级值。
    mount.showChat.value = false;
    await tester.pump();
    mount.showChat.value = true;
    await tester.pump();

    expect(find.byTooltip('取消编辑'), findsNothing);
    _expectFieldText(_composerFinder, 'A 草稿');
  });

  testWidgets('编辑带模板消息：变量输入框携带已保存值，修改后提交新分支', (tester) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['模板回复'])
      ..enqueueChunks(['编辑后模板回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;
    await _seedVariableTemplate(tester, container);

    // 发送带模板消息（变量 '甲'）。
    await _selectTemplate(tester, '变量模板');
    await tester.pump();
    await tester.enterText(_composerFinder, '模板问题');
    await tester.pump();
    await tester.enterText(_variableField('title'), '甲');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '带模板消息首轮生成完成',
    );

    // 编辑该消息：变量框携带 '甲'，改为 '乙' 后提交。气泡按完整可见正文
    // 定位（模板拼接结果为「模板问题\n请按甲输出。」）。
    await _tapEditMessage(tester, '模板问题\n请按甲输出。');
    final titleField = _variableField('title');
    _expectFieldText(titleField, '甲');
    await tester.enterText(titleField, '乙');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '带模板消息编辑提交生成完成',
    );

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
