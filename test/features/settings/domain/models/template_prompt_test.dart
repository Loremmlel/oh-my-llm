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

  group('TemplatePromptVariableType', () {
    test('fromString 正确解析 number', () {
      expect(
        TemplatePromptVariableType.fromString('number'),
        TemplatePromptVariableType.number,
      );
    });

    test('fromString 正确解析 text', () {
      expect(
        TemplatePromptVariableType.fromString('text'),
        TemplatePromptVariableType.text,
      );
    });

    test('fromString 大写不敏感', () {
      expect(
        TemplatePromptVariableType.fromString('Number'),
        TemplatePromptVariableType.number,
      );
    });

    test('fromString 未知值回退为 text', () {
      expect(
        TemplatePromptVariableType.fromString('unknown'),
        TemplatePromptVariableType.text,
      );
    });

    test('fromString null 回退为 text', () {
      expect(
        TemplatePromptVariableType.fromString(null),
        TemplatePromptVariableType.text,
      );
    });
  });

  group('TemplatePromptVariable type', () {
    test('默认类型为 text', () {
      const variable = TemplatePromptVariable(name: '测试');
      expect(variable.type, TemplatePromptVariableType.text);
      expect(variable.isNumber, isFalse);
    });

    test('number 类型的 isNumber 为 true', () {
      const variable = TemplatePromptVariable(
        name: '起始',
        type: TemplatePromptVariableType.number,
      );
      expect(variable.isNumber, isTrue);
    });

    test('toJson 包含 type 字段', () {
      const variable = TemplatePromptVariable(
        name: '起始',
        defaultValue: '1',
        type: TemplatePromptVariableType.number,
      );
      final json = variable.toJson();
      expect(json['type'], 'number');
      expect(json['name'], '起始');
      expect(json['defaultValue'], '1');
    });

    test('fromJson 正确解析 number 类型', () {
      final variable = TemplatePromptVariable.fromJson(const {
        'name': '起始',
        'defaultValue': '1',
        'type': 'number',
      });
      expect(variable.name, '起始');
      expect(variable.defaultValue, '1');
      expect(variable.type, TemplatePromptVariableType.number);
    });

    test('fromJson 向后兼容：无 type 字段时默认为 text', () {
      final variable = TemplatePromptVariable.fromJson(const {
        'name': '旧变量',
        'defaultValue': '值',
      });
      expect(variable.type, TemplatePromptVariableType.text);
    });

    test('copyWith 保留 type', () {
      const variable = TemplatePromptVariable(
        name: '起始',
        type: TemplatePromptVariableType.number,
      );
      final copied = variable.copyWith(defaultValue: '5');
      expect(copied.type, TemplatePromptVariableType.number);
      expect(copied.defaultValue, '5');
    });

    test('copyWith 可以覆盖 type', () {
      const variable = TemplatePromptVariable(
        name: '起始',
        type: TemplatePromptVariableType.number,
      );
      final copied = variable.copyWith(type: TemplatePromptVariableType.text);
      expect(copied.type, TemplatePromptVariableType.text);
    });

    test('props 包含 type', () {
      const v1 = TemplatePromptVariable(
        name: '起始',
        type: TemplatePromptVariableType.number,
      );
      const v2 = TemplatePromptVariable(
        name: '起始',
        type: TemplatePromptVariableType.text,
      );
      expect(v1 == v2, isFalse);
    });
  });
}
