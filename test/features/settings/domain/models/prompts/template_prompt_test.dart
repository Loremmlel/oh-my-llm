import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

void main() {
  test(
    'TemplatePrompt projects input variables and detects the body variable',
    () {
      final prompt = TemplatePrompt(
        id: 't1',
        title: '测试',
        content: '',
        variables: const [
          TemplatePromptVariable(name: templatePromptBodyVariableName),
          TemplatePromptVariable(name: '风格'),
        ],
        updatedAt: DateTime(2026),
      );
      final withoutBody = TemplatePrompt(
        id: 't2',
        title: '测试',
        content: '',
        variables: const [TemplatePromptVariable(name: '风格')],
        updatedAt: DateTime(2026),
      );

      expect(prompt.inputVariables.map((variable) => variable.name), ['风格']);
      expect(prompt.containsBodyVariable, isTrue);
      expect(withoutBody.containsBodyVariable, isFalse);
    },
  );

  test('TemplatePromptVariableType parses known values and safe fallbacks', () {
    const cases = [
      (
        name: 'number',
        value: 'number',
        expected: TemplatePromptVariableType.number,
      ),
      (name: 'text', value: 'text', expected: TemplatePromptVariableType.text),
      (
        name: 'case insensitive',
        value: 'Number',
        expected: TemplatePromptVariableType.number,
      ),
      (
        name: 'unknown',
        value: 'unknown',
        expected: TemplatePromptVariableType.text,
      ),
      (name: 'null', value: null, expected: TemplatePromptVariableType.text),
    ];

    for (final testCase in cases) {
      expect(
        TemplatePromptVariableType.fromString(testCase.value),
        testCase.expected,
        reason: testCase.name,
      );
    }
  });

  test('TemplatePromptVariable exposes text and number type semantics', () {
    const textVariable = TemplatePromptVariable(name: '文本');
    const numberVariable = TemplatePromptVariable(
      name: '起始',
      type: TemplatePromptVariableType.number,
    );

    expect(textVariable.type, TemplatePromptVariableType.text);
    expect(textVariable.isNumber, isFalse);
    expect(numberVariable.isNumber, isTrue);
  });

  test('number variable JSON round-trip preserves every field', () {
    const variable = TemplatePromptVariable(
      name: '起始',
      defaultValue: '1',
      type: TemplatePromptVariableType.number,
    );

    expect(TemplatePromptVariable.fromJson(variable.toJson()), variable);
  });

  test('missing variable type remains backward-compatible with text', () {
    final variable = TemplatePromptVariable.fromJson(const {
      'name': '旧变量',
      'defaultValue': '值',
    });

    expect(variable.type, TemplatePromptVariableType.text);
  });
}
