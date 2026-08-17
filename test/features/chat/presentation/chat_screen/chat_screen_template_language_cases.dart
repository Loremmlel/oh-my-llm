import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart';
import 'package:oh_my_llm/features/settings/application/prompts/template_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../../../helpers/async/widget_test_animation.dart';
import 'chat_screen_test_helpers.dart';

/// 文本/数字变量字段的输入框：按变量名 label 定位，避免与页面其他同名文本混淆。
///
/// select 字段不是 TextField（InputDecorator + DropdownButton），不适用本 finder，
/// 需用当前选中值文本断言其可见性。
Finder _variableField(String name) => find.widgetWithText(TextField, name);

/// 断言字段当前展示的文本（TextField 值）。
void _expectFieldText(Finder field, String text) {
  expect(find.descendant(of: field, matching: find.text(text)), findsWidgets);
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

/// 在单选下拉中选择一个选项：先点当前值打开菜单，再点目标选项。
Future<void> _selectSelectOption(
  WidgetTester tester,
  String currentValue,
  String option,
) async {
  await tester.ensureVisible(find.text(currentValue).first);
  await tester.tap(find.text(currentValue).first);
  await settleOverlayTransition(tester);
  await tester.tap(find.text(option).last);
  await settleOverlayTransition(tester);
}

/// 注册模板并等待渲染（upsert 同步持久化，单帧即可）。
Future<void> _seedTemplate(
  WidgetTester tester,
  ProviderContainer container,
  TemplatePrompt template,
) async {
  await container.read(templatePromptsProvider.notifier).upsert(template);
  await tester.pump();
}

/// 条件模板：select 控制「一/二」分支，各分支携带独立变量。
///
/// 控制变量必须在正文中出现类型化占位符（条件本身不声明变量），
/// 编译器才能解析条件引用。
TemplatePrompt _conditionalTemplate() => TemplatePrompt(
  id: 'tp-cond',
  title: '条件模板',
  content: '''
人称：{{人称:select|一|二}}
{{#if 人称 == "一"}}
一分支：{{主角名}}。
{{else if 人称 == "二"}}
二分支：{{目标名}}。
{{/if}}
''',
  variables: const [
    TemplatePromptVariable(
      name: '人称',
      defaultValue: '一',
      type: TemplatePromptVariableType.select,
      options: ['一', '二'],
    ),
    TemplatePromptVariable(name: '主角名', defaultValue: '阿昭'),
    TemplatePromptVariable(name: '目标名', defaultValue: '阿柚'),
  ],
  updatedAt: DateTime(2026, 5, 5, 0, 1),
);

/// 含顶层变量与条件分支的模板：顶层变量所有分支都可见。
TemplatePrompt _topLevelVariableTemplate() => TemplatePrompt(
  id: 'tp-top',
  title: '顶层变量模板',
  content: '''
风格：{{风格}}
人称：{{人称:select|一|二}}
{{#if 人称 == "一"}}
一分支：{{主角名}}。
{{else}}
二分支：{{目标名}}。
{{/if}}
''',
  variables: const [
    TemplatePromptVariable(name: '风格', defaultValue: '轻快'),
    TemplatePromptVariable(
      name: '人称',
      defaultValue: '一',
      type: TemplatePromptVariableType.select,
      options: ['一', '二'],
    ),
    TemplatePromptVariable(name: '主角名', defaultValue: '阿昭'),
    TemplatePromptVariable(name: '目标名', defaultValue: '阿柚'),
  ],
  updatedAt: DateTime(2026, 5, 5, 0, 2),
);

/// 数字比较模板：按指定运算符与阈值决定「达标/未达标」分支。
TemplatePrompt _numberConditionTemplate({
  required String operator,
  required int threshold,
}) {
  return TemplatePrompt(
    id: 'tp-num-cond',
    title: '数字条件模板',
    content:
        '章：{{章:number}}\n{{#if 章 $operator $threshold}}达标：{{达标项}}。{{else}}未达标：{{未达标项}}。{{/if}}',
    variables: const [
      TemplatePromptVariable(
        name: '章',
        defaultValue: '1',
        type: TemplatePromptVariableType.number,
      ),
      TemplatePromptVariable(name: '达标项', defaultValue: '达'),
      TemplatePromptVariable(name: '未达标项', defaultValue: '未'),
    ],
    updatedAt: DateTime(2026, 5, 5, 0, 3),
  );
}

/// 单选模板：只有 select 变量，用于菜单字符串与消息持久化断言。
TemplatePrompt _selectOnlyTemplate() => TemplatePrompt(
  id: 'tp-select',
  title: '人称模板',
  content: '请用{{人称:select|一|二|三}}。',
  variables: const [
    TemplatePromptVariable(
      name: '人称',
      defaultValue: '一',
      type: TemplatePromptVariableType.select,
      options: ['一', '二', '三'],
    ),
  ],
  updatedAt: DateTime(2026, 5, 5, 0, 4),
);

void registerChatScreenTemplateLanguageTests() {
  testWidgets('选择单选选项切换可见分支字段并改变最终发送文本', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _conditionalTemplate());

    // 默认人称='一'：一分支字段可见，二分支字段隐藏。
    await _selectTemplate(tester, '条件模板');
    await tester.pump();
    expect(_variableField('主角名'), findsOneWidget);
    expect(_variableField('目标名'), findsNothing);

    // 切到 '二'：二分支字段出现，一分支字段隐藏。
    await _selectSelectOption(tester, '一', '二');
    expect(_variableField('主角名'), findsNothing);
    expect(_variableField('目标名'), findsOneWidget);

    // 填写二分支变量并发送：请求文本只含二分支。
    await tester.enterText(_variableField('目标名'), '小铃');
    await tester.pump();
    await tester.enterText(chatMessageComposerFinder, '正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '单选切换分支发送生成完成',
    );

    final sent = fakeClient.requestHistory.single
        .map((m) => m.content)
        .join('\n');
    expect(sent, contains('二分支：小铃。'));
    expect(sent, isNot(contains('一分支')));
  });

  testWidgets('条件控制字段在所有分支下都保持可见', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _conditionalTemplate());

    // select 字段的可见性以其当前选中值文本断言。
    await _selectTemplate(tester, '条件模板');
    await tester.pump();
    expect(find.text('一'), findsOneWidget);

    await _selectSelectOption(tester, '一', '二');
    expect(find.text('二'), findsOneWidget);

    await _selectSelectOption(tester, '二', '一');
    expect(find.text('一'), findsOneWidget);
  });

  testWidgets('A 分支输入后切 B 再切回 A 恢复 A 的草稿', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _conditionalTemplate());

    await _selectTemplate(tester, '条件模板');
    await tester.pump();

    // A 分支输入 '甲'。
    await tester.enterText(_variableField('主角名'), '甲');
    await tester.pump();

    // 切到 B：A 字段隐藏，B 字段输入 '乙'。
    await _selectSelectOption(tester, '一', '二');
    expect(_variableField('主角名'), findsNothing);
    await tester.enterText(_variableField('目标名'), '乙');
    await tester.pump();

    // 切回 A：A 字段恢复 '甲'，不是默认值；B 字段隐藏但值保留在草稿。
    await _selectSelectOption(tester, '二', '一');
    expect(_variableField('目标名'), findsNothing);
    _expectFieldText(_variableField('主角名'), '甲');

    // 再切到 B：B 字段恢复 '乙'，而不是默认值。
    await _selectSelectOption(tester, '一', '二');
    expect(_variableField('主角名'), findsNothing);
    _expectFieldText(_variableField('目标名'), '乙');
  });

  testWidgets('条件外声明的变量在所有分支下都保持可见', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _topLevelVariableTemplate());

    await _selectTemplate(tester, '顶层变量模板');
    await tester.pump();
    expect(_variableField('风格'), findsOneWidget);
    expect(_variableField('主角名'), findsOneWidget);
    expect(_variableField('目标名'), findsNothing);

    await _selectSelectOption(tester, '一', '二');
    expect(_variableField('风格'), findsOneWidget);
    expect(_variableField('目标名'), findsOneWidget);
    expect(_variableField('主角名'), findsNothing);
  });

  for (final entry in _numberBoundaryCases.entries) {
    testWidgets('数字比较 ${entry.key} 边界值切换分支', (tester) async {
      final fakeClient = FakeChatGenerationClient();
      await pumpChatScreen(tester, fakeClient: fakeClient);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await _seedTemplate(
        tester,
        container,
        _numberConditionTemplate(operator: entry.key, threshold: 3),
      );

      await _selectTemplate(tester, '数字条件模板');
      await tester.pump();

      // 输入使条件成立的边界值：达标分支可见。
      await tester.enterText(_variableField('章'), '${entry.value.trueValue}');
      await tester.pump();
      expect(_variableField('达标项'), findsOneWidget);
      expect(_variableField('未达标项'), findsNothing);

      // 输入使条件不成立的边界值：未达标分支可见。
      await tester.enterText(_variableField('章'), '${entry.value.falseValue}');
      await tester.pump();
      expect(_variableField('未达标项'), findsOneWidget);
      expect(_variableField('达标项'), findsNothing);
    });
  }

  testWidgets('select 菜单值是声明字符串，消息持久化字符串而非列表索引', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['已收到']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _selectOnlyTemplate());

    await _selectTemplate(tester, '人称模板');
    await tester.pump();

    // 打开下拉：菜单项是声明的字符串。
    await tester.tap(find.text('一').first);
    await settleOverlayTransition(tester);
    expect(find.text('一'), findsWidgets);
    expect(find.text('二'), findsWidgets);
    expect(find.text('三'), findsWidgets);

    // 选择 '二' 并发送。
    await tester.tap(find.text('二').last);
    await settleOverlayTransition(tester);
    await tester.enterText(chatMessageComposerFinder, '正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: 'select 字符串持久化发送生成完成',
    );

    final conversation = container.read(activeChatConversationProvider);
    final userMessage = conversation.messages.firstWhere(
      (m) => m.role == ChatMessageRole.user,
    );
    expect(userMessage.templateVariableValues['人称'], '二');
    expect(
      fakeClient.requestHistory.single.map((m) => m.content).join('\n'),
      contains('请用二。'),
    );
  });

  testWidgets('编辑历史消息：失效 select 值显示当前默认并归一化草稿后发送', (tester) async {
    final fakeClient = FakeChatGenerationClient()
      ..enqueueChunks(['首次回复'])
      ..enqueueChunks(['编辑后回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(tester, container, _selectOnlyTemplate());

    // 发送带 select='二' 的消息。
    await _selectTemplate(tester, '人称模板');
    await tester.pump();
    await _selectSelectOption(tester, '一', '二');
    await tester.enterText(chatMessageComposerFinder, '测试正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '失效 select 用例首轮生成完成',
    );

    // 用同一 ID 更新模板：移除选项 '二'，默认仍为 '一'。
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-select',
            title: '人称模板',
            content: '请用{{人称:select|一|三}}。',
            variables: const [
              TemplatePromptVariable(
                name: '人称',
                defaultValue: '一',
                type: TemplatePromptVariableType.select,
                options: ['一', '三'],
              ),
            ],
            updatedAt: DateTime(2026, 5, 5, 0, 5),
          ),
        );
    await tester.pump();

    // 编辑该消息（气泡完整正文为「测试正文\n请用二。」）。
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ChatMessageBubble, '测试正文\n请用二。'),
        matching: find.byTooltip('编辑消息'),
      ),
    );
    await settleAnimatedWidgetTransition(tester);

    // select 字段显示当前配置默认 '一'，而非失效的 '二'。
    expect(find.text('一'), findsOneWidget);
    expect(find.text('二'), findsNothing);

    // 提交编辑：新分支使用归一化后的默认 '一'。
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '失效 select 用例编辑提交生成完成',
    );

    final afterEdit = container.read(activeChatConversationProvider);
    final editedBranch = afterEdit.messageNodes.firstWhere(
      (m) => m.role == ChatMessageRole.user && m.content.contains('请用一。'),
    );
    expect(editedBranch.templatePromptId, 'tp-select');
    expect(editedBranch.templateVariableValues['人称'], '一');
    expect(fakeClient.requestHistory, hasLength(2));
  });

  testWidgets('损坏模板显示 inline 诊断文本，发送交互不产生请求', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(
      tester,
      container,
      TemplatePrompt(
        id: 'tp-bad',
        title: '损坏模板',
        content: '{{#if 人称 == "一"}}未闭合',
        variables: const [
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '一',
            type: TemplatePromptVariableType.select,
            options: ['一', '二'],
          ),
        ],
        updatedAt: DateTime(2026, 5, 5, 0, 6),
      ),
    );

    await _selectTemplate(tester, '损坏模板');
    await tester.pump();

    // inline 诊断文本（非 SnackBar/Dialog）。
    expect(find.textContaining('模板语法无效'), findsOneWidget);
    expect(find.textContaining('缺少与 {{#if}} 对应的 {{/if}}'), findsOneWidget);

    // 发送交互不产生请求。
    await tester.enterText(chatMessageComposerFinder, '正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump();
    expect(fakeClient.requestHistory, isEmpty);
  });

  testWidgets('数字值「-」显示 inline 字段错误，发送不产生请求', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(
      tester,
      container,
      TemplatePrompt(
        id: 'tp-num',
        title: '章节模板',
        content: '第{{章:number}}章',
        variables: const [
          TemplatePromptVariable(
            name: '章',
            defaultValue: '1',
            type: TemplatePromptVariableType.number,
          ),
        ],
        updatedAt: DateTime(2026, 5, 5, 0, 7),
      ),
    );

    await _selectTemplate(tester, '章节模板');
    await tester.pump();

    // 输入非法数字 '-'：字段显示 inline 错误。
    await tester.enterText(_variableField('章'), '-');
    await tester.pump();
    expect(find.text('「章」必须是整数'), findsOneWidget);

    // 发送交互不产生请求。
    await tester.enterText(chatMessageComposerFinder, '正文');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump();
    expect(fakeClient.requestHistory, isEmpty);
  });

  testWidgets('切换会话不泄漏选中模板、可见分支与隐藏值', (tester) async {
    final fakeClient = FakeChatGenerationClient()..enqueueChunks(['A 回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convAId = container.read(chatSessionsProvider).activeConversation.id;
    await _seedTemplate(tester, container, _conditionalTemplate());

    // A 需要先有一条消息，「新建对话」才有意义。
    await sendMessage(tester, 'A 的问题');
    await waitForChatGeneration(
      tester,
      container,
      (s) => s.generation?.phase == ChatGenerationPhase.succeeded,
      description: '会话泄漏用例 A 首条消息生成完成',
    );

    // A 选择模板，进入二分支并填写隐藏值。
    await _selectTemplate(tester, '条件模板');
    await tester.pump();
    await _selectSelectOption(tester, '一', '二');
    await tester.enterText(_variableField('目标名'), '乙');
    await tester.pump();

    // 新建 B：不继承模板选择，也不显示任何变量字段。
    await tester.tap(find.byTooltip('新建对话').first);
    await tester.pump();
    final convBId = container.read(chatSessionsProvider).activeConversation.id;
    expect(convBId, isNot(convAId));
    expect(_variableField('主角名'), findsNothing);
    expect(_variableField('目标名'), findsNothing);
    expect(find.text('一'), findsNothing);

    // B 选择同一模板：空草稿回落默认分支（一）与默认值，不泄漏 A 的 '乙'。
    await _selectTemplate(tester, '条件模板');
    await tester.pump();
    expect(find.text('一'), findsOneWidget);
    expect(_variableField('主角名'), findsOneWidget);
    expect(_variableField('目标名'), findsNothing);
    _expectFieldText(_variableField('主角名'), '阿昭');
    expect(find.text('乙'), findsNothing);

    // 切回 A：模板选择、可见分支与隐藏值全部恢复。
    container.read(chatSessionsProvider.notifier).selectConversation(convAId);
    await tester.pump();
    expect(find.text('二'), findsOneWidget);
    expect(_variableField('主角名'), findsNothing);
    expect(_variableField('目标名'), findsOneWidget);
    _expectFieldText(_variableField('目标名'), '乙');
  });

  testWidgets('同 ID 模板更新后重新编译新定义并刷新字段，不再渲染旧分支程序', (tester) async {
    final fakeClient = FakeChatGenerationClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await _seedTemplate(
      tester,
      container,
      TemplatePrompt(
        id: 'tp-dyn',
        title: '动态模板',
        content:
            '人称：{{人称:select|一|二}}\n{{#if 人称 == "一"}}一分支：{{甲}}。{{else}}二分支：{{乙}}。{{/if}}',
        variables: const [
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '一',
            type: TemplatePromptVariableType.select,
            options: ['一', '二'],
          ),
          TemplatePromptVariable(name: '甲', defaultValue: '甲值'),
          TemplatePromptVariable(name: '乙', defaultValue: '乙值'),
        ],
        updatedAt: DateTime(2026, 5, 5, 0, 8),
      ),
    );

    await _selectTemplate(tester, '动态模板');
    await tester.pump();
    expect(_variableField('甲'), findsOneWidget);
    expect(_variableField('乙'), findsNothing);

    // 选中旧选项 '二'：该值写入 composer 草稿，更新模板后将变成失效值。
    await _selectSelectOption(tester, '一', '二');

    // 同 ID 更新模板：新选项集、新分支变量、默认切到 '三'。
    await container
        .read(templatePromptsProvider.notifier)
        .upsert(
          TemplatePrompt(
            id: 'tp-dyn',
            title: '动态模板',
            content:
                '人称：{{人称:select|三|四}}\n{{#if 人称 == "三"}}三分支：{{丙}}。{{else}}四分支：{{丁}}。{{/if}}',
            variables: const [
              TemplatePromptVariable(
                name: '人称',
                defaultValue: '三',
                type: TemplatePromptVariableType.select,
                options: ['三', '四'],
              ),
              TemplatePromptVariable(name: '丙', defaultValue: '丙值'),
              TemplatePromptVariable(name: '丁', defaultValue: '丁值'),
            ],
            updatedAt: DateTime(2026, 5, 5, 0, 9),
          ),
        );
    await tester.pump();

    // 旧分支变量被 dispose，新定义按归一化默认 '三' 渲染三分支字段。
    expect(_variableField('甲'), findsNothing);
    expect(_variableField('乙'), findsNothing);
    expect(_variableField('丙'), findsOneWidget);
    expect(_variableField('丁'), findsNothing);
    expect(find.text('三'), findsOneWidget);

    // 失效的 '二' 经 post-frame 归一化写回 composer 草稿（不进入编辑模式
    // 也生效），草稿值与字段展示一致。
    await tester.pump();
    final conversationId = container
        .read(chatSessionsProvider)
        .activeConversation
        .id;
    final draft = container
        .read(composerDraftProvider.notifier)
        .draftFor(conversationId);
    expect(draft.templateVariableValuesByTemplateId['tp-dyn']?['人称'], '三');
  });
}

/// 四种数字比较运算符的边界值：true 表示条件成立、false 表示不成立。
const _numberBoundaryCases = <String, ({int trueValue, int falseValue})>{
  '>': (trueValue: 4, falseValue: 3),
  '>=': (trueValue: 3, falseValue: 2),
  '<': (trueValue: 2, falseValue: 3),
  '<=': (trueValue: 3, falseValue: 4),
};
