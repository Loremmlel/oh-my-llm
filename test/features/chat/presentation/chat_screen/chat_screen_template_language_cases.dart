import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/composer/composer_draft_controller.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
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
        content: '人称：{{人称:select|一|二}}\n{{#if 人称 == "一"}}一分支：{{甲}}。{{else}}二分支：{{乙}}。{{/if}}',
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
            content: '人称：{{人称:select|三|四}}\n{{#if 人称 == "三"}}三分支：{{丙}}。{{else}}四分支：{{丁}}。{{/if}}',
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
