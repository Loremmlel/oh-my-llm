import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_parser.dart';

void main() {
  group('extractTemplatePromptVariableNames', () {
    test('按首次出现顺序提取变量名并去重', () {
      expect(
        extractTemplatePromptVariableNames(
          '请把{{正文}}翻译成{{目标语言}}，并保持{{语气}}。再重复{{目标语言}}。',
        ),
        [templatePromptBodyVariableName, '目标语言', '语气'],
      );
    });

    test('忽略空变量和不完整占位符', () {
      expect(
        extractTemplatePromptVariableNames('abc {{  }} {{未闭合} {{正常}}'),
        ['正常'],
      );
    });

    test('从带类型标记的占位符中提取纯变量名', () {
      expect(
        extractTemplatePromptVariableNames(
          '从{{起始:number}}到{{结束:number}}，语言为{{语言}}。',
        ),
        ['起始', '结束', '语言'],
      );
    });
  });

  group('parseVariableSpec', () {
    test('纯变量名解析为 text 类型', () {
      final spec = parseVariableSpec('目标语言');
      expect(spec.name, '目标语言');
      expect(spec.type, TemplatePromptVariableType.text);
    });

    test(':number 标记解析为 number 类型', () {
      final spec = parseVariableSpec('起始:number');
      expect(spec.name, '起始');
      expect(spec.type, TemplatePromptVariableType.number);
    });

    test('空格被正确 trim', () {
      final spec = parseVariableSpec('  起始 : number  ');
      expect(spec.name, '起始');
      expect(spec.type, TemplatePromptVariableType.number);
    });

    test('未知类型回退为 text', () {
      final spec = parseVariableSpec('变量:unknown');
      expect(spec.name, '变量');
      expect(spec.type, TemplatePromptVariableType.text);
    });

    test('空冒号后缀回退为 text', () {
      final spec = parseVariableSpec('变量:');
      expect(spec.name, '变量');
      expect(spec.type, TemplatePromptVariableType.text);
    });

    test('无冒号分隔符时整体作为变量名', () {
      final spec = parseVariableSpec('普通变量');
      expect(spec.name, '普通变量');
      expect(spec.type, TemplatePromptVariableType.text);
    });
  });

  group('extractTemplatePromptVariableSpecs', () {
    test('返回带类型的完整规格列表', () {
      final specs = extractTemplatePromptVariableSpecs(
        '从{{起始:number}}到{{结束:number}}，语言为{{语言}}。',
      );
      expect(specs.length, 3);
      expect(specs[0].name, '起始');
      expect(specs[0].type, TemplatePromptVariableType.number);
      expect(specs[1].name, '结束');
      expect(specs[1].type, TemplatePromptVariableType.number);
      expect(specs[2].name, '语言');
      expect(specs[2].type, TemplatePromptVariableType.text);
    });

    test('同名变量去重时保留首次出现的类型', () {
      final specs = extractTemplatePromptVariableSpecs(
        '{{计数:number}}，再次{{计数}}。',
      );
      expect(specs.length, 1);
      expect(specs[0].name, '计数');
      expect(specs[0].type, TemplatePromptVariableType.number);
    });
  });

  group('reconcileTemplatePromptVariables', () {
    test('保留同名变量原有默认值', () {
      final result = reconcileTemplatePromptVariables(
        content: '请处理{{正文}}，并补充{{语气}}。',
        existingVariables: const [
          TemplatePromptVariable(name: '语气', defaultValue: '专业'),
        ],
      );

      expect(result, const [
        TemplatePromptVariable(name: templatePromptBodyVariableName),
        TemplatePromptVariable(name: '语气', defaultValue: '专业'),
      ]);
    });

    test('正文变量始终不带默认值', () {
      final result = reconcileTemplatePromptVariables(
        content: '请处理{{正文}}。',
        existingVariables: const [
          TemplatePromptVariable(
            name: templatePromptBodyVariableName,
            defaultValue: '不会保留',
          ),
        ],
      );

      expect(
        result,
        const [TemplatePromptVariable(name: templatePromptBodyVariableName)],
      );
    });

    test('number 类型新变量默认值为 1', () {
      final result = reconcileTemplatePromptVariables(
        content: '从{{起始:number}}开始。',
        existingVariables: const [],
      );

      expect(result.length, 1);
      expect(result[0].name, '起始');
      expect(result[0].type, TemplatePromptVariableType.number);
      expect(result[0].defaultValue, '1');
    });

    test('number 类型保留已有默认值', () {
      final result = reconcileTemplatePromptVariables(
        content: '从{{起始:number}}开始。',
        existingVariables: const [
          TemplatePromptVariable(
            name: '起始',
            defaultValue: '10',
            type: TemplatePromptVariableType.number,
          ),
        ],
      );

      expect(result[0].defaultValue, '10');
      expect(result[0].type, TemplatePromptVariableType.number);
    });

    test('text 类型新变量默认值为空', () {
      final result = reconcileTemplatePromptVariables(
        content: '语言为{{语言}}。',
        existingVariables: const [],
      );

      expect(result[0].name, '语言');
      expect(result[0].type, TemplatePromptVariableType.text);
      expect(result[0].defaultValue, '');
    });

    test('混合 text 和 number 变量', () {
      final result = reconcileTemplatePromptVariables(
        content: '从{{起始:number}}到{{目标语言}}。',
        existingVariables: const [],
      );

      expect(result.length, 2);
      expect(result[0].name, '起始');
      expect(result[0].type, TemplatePromptVariableType.number);
      expect(result[0].defaultValue, '1');
      expect(result[1].name, '目标语言');
      expect(result[1].type, TemplatePromptVariableType.text);
      expect(result[1].defaultValue, '');
    });
  });
}
