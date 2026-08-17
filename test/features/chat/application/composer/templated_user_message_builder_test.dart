import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/composer/templated_user_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';

/// 现场编译模板定义，测试保证模板正文与已保存变量一致。
TemplatePromptCompilation _compile(TemplatePrompt prompt) {
  final compilation = compileTemplatePromptDefinition(prompt);
  expect(compilation.isValid, isTrue, reason: prompt.content);
  return compilation;
}

void main() {
  test('无模板时返回裁剪后的正文且不含模板片段', () {
    final result = buildTemplatedUserMessage(
      body: '  你好  ',
      templatePrompt: null,
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '你好');
    expect(success.message.userMessageSegments, isEmpty);
    expect(success.effectiveVariableValues, isEmpty);
  });

  test('有效的第一人称单选选择首个分支且只含该分支', () {
    final template = TemplatePrompt(
      id: 'tp-select',
      title: '人称模板',
      content:
          '请用{{人称:select|一|二|三}}。'
          '{{#if 人称 == "一"}}我是第一人称'
          '{{else if 人称 == "二"}}你是第二人称'
          '{{else}}他是第三人称{{/if}}',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'人称': '一'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '请用一。我是第一人称');
    expect(success.message.content, isNot(contains('第二人称')));
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(
        text: '请用一。我是第一人称',
        kind: UserMessageSegmentKind.template,
      ),
    ]);
  });

  test('切换人称选中 else if 分支且排除隐藏分支文本', () {
    final template = TemplatePrompt(
      id: 'tp-select',
      title: '人称模板',
      content:
          '请用{{人称:select|一|二|三}}。'
          '{{#if 人称 == "一"}}我是第一人称'
          '{{else if 人称 == "二"}}你是第二人称'
          '{{else}}他是第三人称{{/if}}',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'人称': '二'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '请用二。你是第二人称');
    expect(success.message.content, isNot(contains('第一人称')));
    expect(success.message.content, isNot(contains('第三人称')));
  });

  test('顶层 {{正文}} 在渲染流中生成 body 类型片段', () {
    final template = TemplatePrompt(
      id: 'tp-body',
      title: '翻译模板',
      content: '请把{{正文}}翻译成英文。',
      variables: const [
        TemplatePromptVariable(name: templatePromptBodyVariableName),
      ],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '你好',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '请把你好翻译成英文。');
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(text: '请把', kind: UserMessageSegmentKind.template),
      UserMessageSegment(text: '你好', kind: UserMessageSegmentKind.body),
      UserMessageSegment(text: '翻译成英文。', kind: UserMessageSegmentKind.template),
    ]);
  });

  test('无顶层 {{正文}} 时按旧契约前置正文与换行', () {
    final template = TemplatePrompt(
      id: 'tp-summary',
      title: '总结模板',
      content: '请总结成{{语气}}。',
      variables: const [TemplatePromptVariable(name: '语气', defaultValue: '简洁')],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '原文',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'语气': '简洁'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '原文\n请总结成简洁。');
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(text: '原文\n', kind: UserMessageSegmentKind.body),
      UserMessageSegment(
        text: '请总结成简洁。',
        kind: UserMessageSegmentKind.template,
      ),
    ]);
  });

  test('正文为空且无正文占位符时只渲染模板内容', () {
    final template = TemplatePrompt(
      id: 'tp-empty-body',
      title: '润色模板',
      content: '请输出{{风格}}版总结。',
      variables: const [TemplatePromptVariable(name: '风格', defaultValue: '简洁')],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '   ',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'风格': '专业'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '请输出专业版总结。');
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(
        text: '请输出专业版总结。',
        kind: UserMessageSegmentKind.template,
      ),
    ]);
  });

  test('独占行控制标签不留下缩进与空行，分支正文缩进保留', () {
    final template = TemplatePrompt(
      id: 'tp-indent',
      title: '缩进模板',
      content:
          '视角：{{人称:select|一|三}}\n要求：\n'
          '  {{#if 人称 == "一"}}\n  第一人称。\n  {{/if}}\n{{正文}}',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '三'],
        ),
        TemplatePromptVariable(name: templatePromptBodyVariableName),
      ],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '内容',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'人称': '一'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, '视角：一\n要求：\n  第一人称。\n内容');
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(
        text: '视角：一\n要求：\n  第一人称。\n',
        kind: UserMessageSegmentKind.template,
      ),
      UserMessageSegment(text: '内容', kind: UserMessageSegmentKind.body),
    ]);
  });

  test('编译无效时返回诊断而非部分内容，且不重新编译', () {
    final malformed = TemplatePrompt(
      id: 'tp-malformed',
      title: '损坏模板',
      content: '{{#if x == "a"}}未闭合',
      variables: const [],
      updatedAt: DateTime(2026),
    );
    final invalidCompilation = compileTemplatePromptDefinition(malformed);
    expect(invalidCompilation.isValid, isFalse);

    final result = buildTemplatedUserMessage(
      body: '内容',
      templatePrompt: malformed,
      compilation: invalidCompilation,
      variableValues: const {},
    );

    expect(result, isA<TemplatedUserMessageBuildFailure>());
    final failure = result as TemplatedUserMessageBuildFailure;
    expect(failure.diagnostics, isNotEmpty);
    expect(failure.valueErrors, isEmpty);

    // 编译缺失时同样直接失败，builder 内部绝不重新编译。
    final noCompilation = buildTemplatedUserMessage(
      body: '内容',
      templatePrompt: malformed,
    );
    expect(noCompilation, isA<TemplatedUserMessageBuildFailure>());
  });

  test('非法数字与非法单选输入返回值错误而非猜测分支', () {
    final numberTemplate = TemplatePrompt(
      id: 'tp-num',
      title: '数字模板',
      content: '{{n:number}}{{#if n >= 2}}多{{/if}}',
      variables: const [
        TemplatePromptVariable(
          name: 'n',
          defaultValue: '1',
          type: TemplatePromptVariableType.number,
        ),
      ],
      updatedAt: DateTime(2026),
    );
    final numberResult = buildTemplatedUserMessage(
      body: '',
      templatePrompt: numberTemplate,
      compilation: _compile(numberTemplate),
      variableValues: const {'n': 'abc'},
    );
    expect(numberResult, isA<TemplatedUserMessageBuildFailure>());
    final numberFailure = numberResult as TemplatedUserMessageBuildFailure;
    expect(numberFailure.diagnostics, isEmpty);
    expect(numberFailure.valueErrors.single.variableName, 'n');
    expect(
      numberFailure.valueErrors.single.code,
      TemplatePromptValueErrorCode.invalidNumber,
    );

    final selectTemplate = TemplatePrompt(
      id: 'tp-select-bad',
      title: '单选模板',
      content: '{{人称:select|一|二|三}}{{#if 人称 == "一"}}A{{/if}}',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '一',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026),
    );
    final selectResult = buildTemplatedUserMessage(
      body: '',
      templatePrompt: selectTemplate,
      compilation: _compile(selectTemplate),
      variableValues: const {'人称': '四'},
    );
    expect(selectResult, isA<TemplatedUserMessageBuildFailure>());
    final selectFailure = selectResult as TemplatedUserMessageBuildFailure;
    expect(selectFailure.valueErrors.single.variableName, '人称');
    expect(
      selectFailure.valueErrors.single.code,
      TemplatePromptValueErrorCode.invalidSelectValue,
    );
  });

  test('省略或空的单选输入使用配置默认值写入有效值', () {
    final template = TemplatePrompt(
      id: 'tp-select-default',
      title: '默认单选模板',
      content: '请用{{人称:select|一|二|三}}。',
      variables: const [
        TemplatePromptVariable(
          name: '人称',
          defaultValue: '二',
          type: TemplatePromptVariableType.select,
          options: ['一', '二', '三'],
        ),
      ],
      updatedAt: DateTime(2026),
    );

    final omitted = buildTemplatedUserMessage(
      body: '',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {},
    );
    expect(omitted, isA<TemplatedUserMessageBuildSuccess>());
    final omittedSuccess = omitted as TemplatedUserMessageBuildSuccess;
    expect(omittedSuccess.effectiveVariableValues, {'人称': '二'});
    expect(omittedSuccess.message.content, '请用二。');

    final emptyInput = buildTemplatedUserMessage(
      body: '',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'人称': '  '},
    );
    expect(emptyInput, isA<TemplatedUserMessageBuildSuccess>());
    expect(
      (emptyInput as TemplatedUserMessageBuildSuccess).effectiveVariableValues,
      {'人称': '二'},
    );
  });

  test('相邻同类片段合并为一个 UserMessageSegment', () {
    final template = TemplatePrompt(
      id: 'tp-merge',
      title: '合并模板',
      content: '{{x}}{{y}}尾',
      variables: const [
        TemplatePromptVariable(name: 'x', defaultValue: 'a'),
        TemplatePromptVariable(name: 'y', defaultValue: 'b'),
      ],
      updatedAt: DateTime(2026),
    );

    final result = buildTemplatedUserMessage(
      body: '',
      templatePrompt: template,
      compilation: _compile(template),
      variableValues: const {'x': 'a', 'y': 'b'},
    );

    expect(result, isA<TemplatedUserMessageBuildSuccess>());
    final success = result as TemplatedUserMessageBuildSuccess;
    expect(success.message.content, 'ab尾');
    expect(success.message.userMessageSegments, const [
      UserMessageSegment(text: 'ab尾', kind: UserMessageSegmentKind.template),
    ]);
  });
}
