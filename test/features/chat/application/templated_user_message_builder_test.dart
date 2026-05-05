import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/templated_user_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

void main() {
  test('buildTemplatedUserMessage returns raw body when template is null', () {
    final result = buildTemplatedUserMessage(body: '你好', templatePrompt: null);

    expect(result.content, '你好');
    expect(result.userMessageSegments, isEmpty);
  });

  test('buildTemplatedUserMessage injects body and variables into template', () {
    final result = buildTemplatedUserMessage(
      body: '你好',
      templatePrompt: TemplatePrompt(
        id: 'tp-1',
        title: '翻译模板',
        content: '请把{{正文}}翻译成{{目标语言}}。',
        variables: const [
          TemplatePromptVariable(name: templatePromptBodyVariableName),
          TemplatePromptVariable(name: '目标语言', defaultValue: '英文'),
        ],
        updatedAt: DateTime(2026),
      ),
      variableValues: const {'目标语言': '法文'},
    );

    expect(result.content, '请把你好翻译成法文。');
    expect(result.userMessageSegments, const [
      UserMessageSegment(text: '请把', kind: UserMessageSegmentKind.template),
      UserMessageSegment(text: '你好', kind: UserMessageSegmentKind.body),
      UserMessageSegment(
        text: '翻译成法文。',
        kind: UserMessageSegmentKind.template,
      ),
    ]);
  });

  test('buildTemplatedUserMessage inserts body above template without 正文 placeholder', () {
    final result = buildTemplatedUserMessage(
      body: '原文',
      templatePrompt: TemplatePrompt(
        id: 'tp-2',
        title: '总结模板',
        content: '请总结成{{语气}}。',
        variables: const [
          TemplatePromptVariable(name: '语气', defaultValue: '简洁'),
        ],
        updatedAt: DateTime(2026),
      ),
      variableValues: const {'语气': '简洁'},
    );

    expect(result.content, '原文\n请总结成简洁。');
    expect(result.userMessageSegments, const [
      UserMessageSegment(text: '原文\n', kind: UserMessageSegmentKind.body),
      UserMessageSegment(
        text: '请总结成简洁。',
        kind: UserMessageSegmentKind.template,
      ),
    ]);
  });
}
