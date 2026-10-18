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
}
