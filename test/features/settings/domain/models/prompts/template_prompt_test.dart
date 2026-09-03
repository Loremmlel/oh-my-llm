import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

void main() {
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

  test('select 变量 JSON 往返保留字符串选项且未知类型仍回退 text', () {
    const variable = TemplatePromptVariable(
      name: '人称',
      defaultValue: '二',
      type: TemplatePromptVariableType.select,
      options: ['一', '二', '三'],
    );

    expect(TemplatePromptVariable.fromJson(variable.toJson()), variable);
    expect(variable.isSelect, isTrue);
    expect(
      TemplatePromptVariable.fromJson(const {
        'name': '旧变量',
        'type': 'future-type',
      }).type,
      TemplatePromptVariableType.text,
    );
  });
}
