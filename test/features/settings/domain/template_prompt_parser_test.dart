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
  });
}
