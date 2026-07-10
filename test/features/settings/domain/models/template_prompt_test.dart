import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

void main() {
  group('TemplatePrompt', () {
    final now = DateTime(2026);
    const bodyVar = TemplatePromptVariable(name: '正文');
    const inputVar = TemplatePromptVariable(name: '风格');

    test('inputVariables 排除正文变量', () {
      final prompt = TemplatePrompt(
        id: 't1',
        title: '测试',
        content: '',
        variables: [bodyVar, inputVar],
        updatedAt: now,
      );
      expect(prompt.inputVariables, [inputVar]);
    });

    test('containsBodyVariable 为 true 当存在正文变量', () {
      final prompt = TemplatePrompt(
        id: 't2',
        title: '测试',
        content: '',
        variables: [bodyVar],
        updatedAt: now,
      );
      expect(prompt.containsBodyVariable, isTrue);
    });

    test('containsBodyVariable 为 false 当不存在正文变量', () {
      final prompt = TemplatePrompt(
        id: 't3',
        title: '测试',
        content: '',
        variables: [inputVar],
        updatedAt: now,
      );
      expect(prompt.containsBodyVariable, isFalse);
    });
  });
}
