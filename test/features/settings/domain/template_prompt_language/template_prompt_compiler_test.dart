import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';

void main() {
  group('变量声明提取', () {
    test('plain、number、select 与顶层正文声明按首次出现顺序解析', () {
      const content = '请{{语气}}。从{{起始:number}}开始，用{{人称:select|一|二|三}}。{{正文}}';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final program = result.program!;
      expect(program.containsBodyVariable, isTrue);
      expect(program.declarations.map((variable) => variable.name), [
        '语气',
        '起始',
        '人称',
        templatePromptBodyVariableName,
      ]);
      expect(program.declarations[0].type, TemplatePromptVariableType.text);
      expect(program.declarations[1].type, TemplatePromptVariableType.number);
      expect(program.declarations[1].defaultValue, '1');
      expect(program.declarations[2].type, TemplatePromptVariableType.select);
      expect(program.declarations[2].options, ['一', '二', '三']);
      expect(program.declarations[2].defaultValue, '一');
      expect(program.inputVariables.map((variable) => variable.name), [
        '语气',
        '起始',
        '人称',
      ]);
    });

    test('带类型声明晚于普通引用时统一解析为一个 select 变量', () {
      final result = compileTemplatePromptContent(
        '{{人称}} / {{人称:select|一|二|三}}',
      );

      expect(result.diagnostics, isEmpty);
      final declaration = result.program!.declarations.single;
      expect(declaration.name, '人称');
      expect(declaration.type, TemplatePromptVariableType.select);
      expect(declaration.options, ['一', '二', '三']);
    });

    test('select 选项去除两端空白并按声明顺序保留', () {
      final result = compileTemplatePromptContent('{{人称:select| 一 |二 | 三}}');

      expect(result.isValid, isTrue);
      expect(result.program!.declarations.single.options, ['一', '二', '三']);
    });

    test('未转义的 | 始终是选项分隔符，无法成为选项内容', () {
      final result = compileTemplatePromptContent('{{x:select|a|b|c}}');

      expect(result.isValid, isTrue);
      expect(result.program!.declarations.single.options, ['a', 'b', 'c']);
    });

    test('select 选项不足、为空或重复时返回 invalidSelectOptions', () {
      const cases = [
        '{{x:select}}',
        '{{x:select|一}}',
        '{{x:select|一||二}}',
        '{{x:select|一|二|}}',
        '{{x:select|一|一}}',
        '{{x:select| 一 |一}}',
      ];
      for (final content in cases) {
        final result = compileTemplatePromptContent(content);
        expect(result.program, isNull, reason: content);
        expect(
          result.diagnostics.where(
            (item) => item.code == TemplatePromptErrorCode.invalidSelectOptions,
          ),
          isNotEmpty,
          reason: content,
        );
      }
    });

    test('同名变量的重复类型声明必须类型与选项一致', () {
      expect(
        compileTemplatePromptContent('{{x:number}}{{x:number}}').diagnostics,
        isEmpty,
      );
      expect(
        compileTemplatePromptContent(
          '{{x:select|a|b}}{{x:select|a|b}}',
        ).diagnostics,
        isEmpty,
      );

      const conflictingCases = [
        '{{x:number}}{{x:select|a|b}}',
        '{{x:select|a|b}}{{x:number}}',
        '{{x:select|a|b}}{{x:select|c|d}}',
        '{{x:select|a|b}}{{x:select|a|c}}',
      ];
      for (final content in conflictingCases) {
        final result = compileTemplatePromptContent(content);
        expect(result.program, isNull, reason: content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.conflictingVariableDeclaration),
          reason: content,
        );
      }
    });

    test('空占位符、数字变量携带选项等返回 invalidPlaceholder', () {
      const cases = [
        '{{  }}',
        '{{x:number|一|二}}',
        '{{a|b}}',
        '{{:select|一|二}}',
      ];
      for (final content in cases) {
        final result = compileTemplatePromptContent(content);
        expect(result.program, isNull, reason: content);
        expect(
          result.diagnostics.where(
            (item) => item.code == TemplatePromptErrorCode.invalidPlaceholder,
          ),
          isNotEmpty,
          reason: content,
        );
      }
    });

    test('正文携带类型标记返回 invalidBodyDeclaration', () {
      for (final content in ['{{正文:number}}', '{{正文:select|一|二}}']) {
        final result = compileTemplatePromptContent(content);
        expect(result.program, isNull, reason: content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.invalidBodyDeclaration),
          reason: content,
        );
      }
    });
  });

  group('条件块解析', () {
    test('if、else if 与 else 分支按顺序解析为条件块', () {
      const content =
          '{{人称:select|一|二|三}}'
          '{{#if 人称 == "一"}}第一人称'
          '{{else if 人称 == "二"}}第二人称'
          '{{else}}第三人称{{/if}}';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final ifNode = result.program!.nodes
          .whereType<TemplatePromptIfNode>()
          .single;
      expect(ifNode.branches, hasLength(2));
      expect(ifNode.branches[0].condition.variableName, '人称');
      expect(
        ifNode.branches[0].condition.operator,
        TemplatePromptComparisonOperator.equal,
      );
      expect(
        ifNode.branches[0].condition.literal,
        const TemplatePromptStringLiteral('一'),
      );
      expect(ifNode.branches[0].nodes, const [TemplatePromptTextNode('第一人称')]);
      expect(
        ifNode.branches[1].condition.literal,
        const TemplatePromptStringLiteral('二'),
      );
      expect(ifNode.branches[1].nodes, const [TemplatePromptTextNode('第二人称')]);
      expect(ifNode.elseNodes, const [TemplatePromptTextNode('第三人称')]);
    });

    test('多个并列条件块互不嵌套', () {
      const content =
          '{{a}}{{b}}{{#if a == "1"}}A{{/if}}'
          '{{#if b == "2"}}B{{/if}}';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      expect(
        result.program!.nodes.whereType<TemplatePromptIfNode>(),
        hasLength(2),
      );
    });

    test('条件引用变量集合按条件收集', () {
      const content =
          '{{人称:select|一|二|三}}{{#if 人称 == "一"}}a{{/if}}'
          '{{章节}}';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      expect(result.program!.conditionVariableNames, {'人称'});
    });
  });

  group('错误码与位置', () {
    test('未闭合条件块返回 unclosedIf 与起始标签位置', () {
      final result = compileTemplatePromptContent('{{#if 人称 == "一"}}\n未闭合内容');

      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == TemplatePromptErrorCode.unclosedIf,
      );
      expect(diagnostic.location.offset, 0);
      expect(diagnostic.location.line, 1);
      expect(diagnostic.location.column, 1);
    });

    test('嵌套 if 返回稳定错误码和内层标签位置', () {
      final result = compileTemplatePromptContent(
        '{{#if 人称 == "一"}}\n{{#if 风格 == "短"}}x{{/if}}\n{{/if}}',
      );

      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == TemplatePromptErrorCode.nestedIf,
      );
      expect(diagnostic.location.line, 2);
      expect(diagnostic.location.column, 1);
    });

    test('条件分支内的正文返回 bodyInsideConditional 与精确位置', () {
      final result = compileTemplatePromptContent(
        '{{#if 人称 == "一"}}\n{{正文}}\n{{/if}}',
      );

      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.code == TemplatePromptErrorCode.bodyInsideConditional,
      );
      expect(diagnostic.location.line, 2);
      expect(diagnostic.location.column, 1);
    });

    test('未声明条件变量返回 undefinedConditionVariable', () {
      final result = compileTemplatePromptContent('{{#if 未声明 == "x"}}a{{/if}}');

      expect(
        result.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.undefinedConditionVariable),
      );
    });

    test('不适用变量类型的运算符返回 invalidConditionOperator', () {
      final result = compileTemplatePromptContent(
        '{{文本}}{{#if 文本 > "a"}}x{{/if}}',
      );

      expect(
        result.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.invalidConditionOperator),
      );
    });

    test('条件语法错误返回 invalidConditionSyntax', () {
      const cases = ['{{#if 人称}}', '{{#if}}', '{{#if a == "x" b}}'];
      for (final content in cases) {
        final result = compileTemplatePromptContent(content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.invalidConditionSyntax),
          reason: content,
        );
      }
    });

    test('字面量类型与变量不符时返回 invalidConditionLiteral', () {
      const cases = [
        '{{文本}}{{#if 文本 == 5}}x{{/if}}',
        '{{n:number}}{{#if n == "x"}}x{{/if}}',
        '{{n:number}}{{#if n == 1.5}}x{{/if}}',
        '{{n:number}}{{#if n == abc}}x{{/if}}',
        '{{人称:select|一|二|三}}{{#if 人称 == "四"}}x{{/if}}',
      ];
      for (final content in cases) {
        final result = compileTemplatePromptContent(content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.invalidConditionLiteral),
          reason: content,
        );
      }
    });

    test('缺少或无法识别的控制标签返回 unexpectedControlTag', () {
      const cases = [
        '{{/if}}',
        '{{else}}',
        '{{else if 人称 == "一"}}',
        '{{#foo}}',
        '{{else 附加内容}}',
      ];
      for (final content in cases) {
        final result = compileTemplatePromptContent(content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.unexpectedControlTag),
          reason: content,
        );
      }
    });

    test('else 后继续出现 else if 返回 elseIfAfterElse，重复 else 返回 duplicateElse', () {
      final afterElse = compileTemplatePromptContent(
        '{{a}}{{b}}{{#if a == "1"}}x{{else}}y{{else if b == "2"}}z{{/if}}',
      );
      expect(
        afterElse.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.elseIfAfterElse),
      );

      final duplicate = compileTemplatePromptContent(
        '{{a}}{{#if a == "1"}}x{{else}}y{{else}}z{{/if}}',
      );
      expect(
        duplicate.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.duplicateElse),
      );
    });
  });

  group('字面量与转义', () {
    test('字符串字面量保留内部空白并支持 \\" 与 \\\\ 转义', () {
      final preserved = compileTemplatePromptContent(
        '{{x}}{{#if x == " 一 "}}a{{/if}}',
      );
      final preservedNode = preserved.program!.nodes
          .whereType<TemplatePromptIfNode>()
          .single;
      expect(
        preservedNode.branches.single.condition.literal,
        const TemplatePromptStringLiteral(' 一 '),
      );

      final escapedQuote = compileTemplatePromptContent(
        '{{x}}{{#if x == "a\\"b"}}a{{/if}}',
      );
      final quoteNode = escapedQuote.program!.nodes
          .whereType<TemplatePromptIfNode>()
          .single;
      expect(
        quoteNode.branches.single.condition.literal,
        const TemplatePromptStringLiteral('a"b'),
      );

      final escapedBackslash = compileTemplatePromptContent(
        '{{x}}{{#if x == "a\\\\b"}}a{{/if}}',
      );
      final backslashNode = escapedBackslash.program!.nodes
          .whereType<TemplatePromptIfNode>()
          .single;
      expect(
        backslashNode.branches.single.condition.literal,
        const TemplatePromptStringLiteral('a\\b'),
      );
    });

    test('不支持的转义返回 invalidConditionLiteral', () {
      final result = compileTemplatePromptContent(
        '{{x}}{{#if x == "a\\nb"}}a{{/if}}',
      );

      expect(
        result.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.invalidConditionLiteral),
      );
    });
  });

  group('控制标签行裁剪', () {
    test('独占行控制标签连同缩进与行尾一起裁剪', () {
      const content =
          '{{人称}}写作要求：\n'
          '{{#if 人称 == "一"}}\n'
          '使用第一人称。\n'
          '{{else}}\n'
          '使用第三人称。\n'
          '{{/if}}\n'
          '正文如下：';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final nodes = result.program!.nodes;
      expect(nodes, hasLength(4));
      expect(nodes[0], const TemplatePromptVariableNode('人称'));
      expect(nodes[1], const TemplatePromptTextNode('写作要求：\n'));
      final ifNode = nodes[2] as TemplatePromptIfNode;
      expect(ifNode.branches.single.nodes, const [
        TemplatePromptTextNode('使用第一人称。\n'),
      ]);
      expect(ifNode.elseNodes, const [TemplatePromptTextNode('使用第三人称。\n')]);
      expect(nodes[3], const TemplatePromptTextNode('正文如下：'));
    });

    test('CRLF 行尾的独占行控制标签同样整行裁剪', () {
      const content =
          '{{人称}}\r\n'
          '{{#if 人称 == "一"}}\r\n'
          '使用第一人称。\r\n'
          '{{/if}}\r\n'
          '结尾';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final nodes = result.program!.nodes;
      expect(nodes, hasLength(4));
      expect(nodes[0], const TemplatePromptVariableNode('人称'));
      expect(nodes[1], const TemplatePromptTextNode('\r\n'));
      final ifNode = nodes[2] as TemplatePromptIfNode;
      expect(ifNode.branches.single.nodes, const [
        TemplatePromptTextNode('使用第一人称。\r\n'),
      ]);
      expect(nodes[3], const TemplatePromptTextNode('结尾'));
    });

    test('带缩进与尾随空格的独占行控制标签裁剪整行', () {
      const content =
          '{{人称}}前\n'
          '  {{#if 人称 == "一"}}  \n'
          'B\n'
          '{{/if}}\n'
          '后';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final nodes = result.program!.nodes;
      expect(nodes, hasLength(4));
      expect(nodes[0], const TemplatePromptVariableNode('人称'));
      expect(nodes[1], const TemplatePromptTextNode('前\n'));
      final ifNode = nodes[2] as TemplatePromptIfNode;
      expect(ifNode.branches.single.nodes, const [
        TemplatePromptTextNode('B\n'),
      ]);
      expect(nodes[3], const TemplatePromptTextNode('后'));
    });

    test('与正文同行的控制标签仅移除标签本身并保留周边空白', () {
      const content =
          '{{人称}}视角：'
          '{{#if 人称 == "一"}}第一人称'
          '{{else}}第三人称{{/if}}。';
      final result = compileTemplatePromptContent(content);

      expect(result.isValid, isTrue);
      final nodes = result.program!.nodes;
      expect(nodes, hasLength(4));
      expect(nodes[1], const TemplatePromptTextNode('视角：'));
      final ifNode = nodes[2] as TemplatePromptIfNode;
      expect(ifNode.branches.single.nodes, const [
        TemplatePromptTextNode('第一人称'),
      ]);
      expect(ifNode.elseNodes, const [TemplatePromptTextNode('第三人称')]);
      expect(nodes[3], const TemplatePromptTextNode('。'));
    });
  });

  group('旧行为兼容', () {
    test('未匹配的旧版非控制占位符保持文本，未闭合的 {{#if 诊断为控制错误', () {
      final unmatched = compileTemplatePromptContent('前置 {{未闭合} 后置');
      expect(unmatched.isValid, isTrue);
      expect(unmatched.program!.nodes, const [
        TemplatePromptTextNode('前置 {{未闭合} 后置'),
      ]);

      final incomplete = compileTemplatePromptContent('{{#if 人称 == "一"');
      expect(
        incomplete.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.unexpectedControlTag),
      );
    });
  });

  group('组合条件与未激活分支', () {
    test('组合条件、变量右值与未激活分支中的错误均被拒绝', () {
      for (final content in [
        '{{a}}{{#if a && b == "1"}}x{{/if}}',
        '{{a}}{{#if a || b == "1"}}x{{/if}}',
      ]) {
        final result = compileTemplatePromptContent(content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.invalidConditionSyntax),
          reason: content,
        );
      }

      final variableRhs = compileTemplatePromptContent(
        '{{a}}{{#if a == b}}x{{/if}}',
      );
      expect(
        variableRhs.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.invalidConditionLiteral),
      );

      final inactiveBranch = compileTemplatePromptContent(
        '{{a:select|1|2}}{{b:select|3|4}}'
        '{{#if a == "1"}}A{{else}}{{#if b == "3"}}B{{/if}}{{/if}}',
      );
      expect(
        inactiveBranch.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.nestedIf),
      );
    });
  });

  group('compileTemplatePromptDefinition', () {
    test('有效定义返回携带已保存默认值的程序', () {
      final prompt = TemplatePrompt(
        id: 't1',
        title: '模板',
        content: '{{人称:select|一|二|三}}{{起始:number}}',
        variables: const [
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '二',
            type: TemplatePromptVariableType.select,
            options: ['一', '二', '三'],
          ),
          TemplatePromptVariable(
            name: '起始',
            defaultValue: '10',
            type: TemplatePromptVariableType.number,
          ),
        ],
        updatedAt: DateTime(2026),
      );

      final result = compileTemplatePromptDefinition(prompt);
      expect(result.isValid, isTrue);
      expect(result.program!.declarations[0].defaultValue, '二');
      expect(result.program!.declarations[1].defaultValue, '10');
    });

    test('正文携带类型时定义编译透传内容诊断', () {
      final prompt = TemplatePrompt(
        id: 't1',
        title: '模板',
        content: '{{正文:number}}',
        variables: const [],
        updatedAt: DateTime(2026),
      );

      final result = compileTemplatePromptDefinition(prompt);
      expect(result.isValid, isFalse);
      expect(
        result.diagnostics.map((item) => item.code).toList(),
        contains(TemplatePromptErrorCode.invalidBodyDeclaration),
      );
    });

    test('模型与正文变量形状不一致时返回 inconsistentStoredVariables', () {
      final cases = <(String, List<TemplatePromptVariable>)>[
        ('{{语气}}', const [TemplatePromptVariable(name: '其他')]),
        (
          '{{起始:number}}',
          const [
            TemplatePromptVariable(
              name: '起始',
              type: TemplatePromptVariableType.text,
            ),
          ],
        ),
        (
          '{{人称:select|一|二|三}}',
          const [
            TemplatePromptVariable(
              name: '人称',
              type: TemplatePromptVariableType.select,
              options: ['一', '二'],
            ),
          ],
        ),
        (
          '{{起始:number}}',
          const [
            TemplatePromptVariable(
              name: '起始',
              defaultValue: 'abc',
              type: TemplatePromptVariableType.number,
            ),
          ],
        ),
        (
          '{{人称:select|一|二|三}}',
          const [
            TemplatePromptVariable(
              name: '人称',
              defaultValue: '四',
              type: TemplatePromptVariableType.select,
              options: ['一', '二', '三'],
            ),
          ],
        ),
        ('{{语气}}{{起始:number}}', const [TemplatePromptVariable(name: '语气')]),
      ];
      for (final (content, variables) in cases) {
        final prompt = TemplatePrompt(
          id: 't1',
          title: '模板',
          content: content,
          variables: variables,
          updatedAt: DateTime(2026),
        );
        final result = compileTemplatePromptDefinition(prompt);
        expect(result.isValid, isFalse, reason: content);
        expect(
          result.diagnostics.map((item) => item.code).toList(),
          contains(TemplatePromptErrorCode.inconsistentStoredVariables),
          reason: content,
        );
      }
    });
  });

  group('reconcileCompiledTemplatePromptVariables', () {
    test('保留有效默认值，正文不带默认值', () {
      final program = compileTemplatePromptContent(
        '{{语气}}{{起始:number}}{{人称:select|一|二|三}}{{正文}}',
      ).program!;
      final reconciled = reconcileCompiledTemplatePromptVariables(
        program: program,
        existingVariables: const [
          TemplatePromptVariable(name: '语气', defaultValue: '专业'),
          TemplatePromptVariable(
            name: '起始',
            defaultValue: '10',
            type: TemplatePromptVariableType.number,
          ),
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '二',
            type: TemplatePromptVariableType.select,
            options: ['一', '二', '三'],
          ),
        ],
      );

      expect(reconciled.map((variable) => variable.name), [
        '语气',
        '起始',
        '人称',
        templatePromptBodyVariableName,
      ]);
      expect(reconciled[0].defaultValue, '专业');
      expect(reconciled[1].defaultValue, '10');
      expect(reconciled[2].defaultValue, '二');
      expect(reconciled[2].options, ['一', '二', '三']);
      expect(reconciled[3].defaultValue, '');
    });

    test('新建数字默认 1，新建单选默认首个选项', () {
      final program = compileTemplatePromptContent(
        '{{语气}}{{起始:number}}{{人称:select|一|二|三}}',
      ).program!;
      final reconciled = reconcileCompiledTemplatePromptVariables(
        program: program,
        existingVariables: const [],
      );

      expect(reconciled[0].defaultValue, '');
      expect(reconciled[1].defaultValue, '1');
      expect(reconciled[2].defaultValue, '一');
    });

    test('单选配置默认值失效时回落到首个选项', () {
      final program = compileTemplatePromptContent(
        '{{人称:select|一|二|三}}',
      ).program!;
      final reconciled = reconcileCompiledTemplatePromptVariables(
        program: program,
        existingVariables: const [
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '四',
            type: TemplatePromptVariableType.select,
            options: ['一', '二', '三'],
          ),
        ],
      );

      expect(reconciled.single.defaultValue, '一');
    });
  });
}
