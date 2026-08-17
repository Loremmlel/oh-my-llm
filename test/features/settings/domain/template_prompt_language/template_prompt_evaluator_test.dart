import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart';

/// 现场编译模板并求值，编译器应保证程序有效。
TemplatePromptEvaluation _evaluate(
  String content, {
  String body = '',
  Map<String, String> values = const {},
}) {
  final compilation = compileTemplatePromptContent(content);
  expect(compilation.isValid, isTrue, reason: content);
  return evaluateTemplatePrompt(
    program: compilation.program!,
    body: body,
    variableValues: values,
  );
}

void main() {
  group('条件求值', () {
    test('文本变量支持 == 与 != 条件', () {
      final hit = _evaluate(
        '{{x}}{{#if x == "a"}}命中{{/if}}',
        values: const {'x': 'a'},
      );
      expect(hit.isValid, isTrue);
      expect(hit.content, 'a命中');

      final miss = _evaluate(
        '{{x}}{{#if x == "a"}}命中{{/if}}',
        values: const {'x': 'b'},
      );
      expect(miss.content, 'b');

      final notEqual = _evaluate(
        '{{x}}{{#if x != "a"}}不同{{/if}}',
        values: const {'x': 'b'},
      );
      expect(notEqual.content, 'b不同');
    });

    test('select 变量支持 == 与 != 条件', () {
      final hit = _evaluate(
        '{{人称:select|一|二|三}}{{#if 人称 == "一"}}第一人称{{/if}}',
        values: const {'人称': '一'},
      );
      expect(hit.content, '一第一人称');

      final notEqual = _evaluate(
        '{{人称:select|一|二|三}}{{#if 人称 != "一"}}其他{{/if}}',
        values: const {'人称': '二'},
      );
      expect(notEqual.content, '二其他');
    });

    test('字符串比较区分大小写', () {
      final result = _evaluate(
        '{{x}}{{#if x == "A"}}命中{{/if}}',
        values: const {'x': 'a'},
      );
      expect(result.content, 'a');
    });

    test('数字六种运算符与负整数', () {
      const content =
          '{{n:number}}'
          '{{#if n > 0}}大于零{{/if}}'
          '{{#if n >= 0}}非负{{/if}}'
          '{{#if n < 0}}小于零{{/if}}'
          '{{#if n <= 0}}非正{{/if}}'
          '{{#if n == -5}}等于负五{{/if}}'
          '{{#if n != -5}}不等于负五{{/if}}';

      final negative = _evaluate(content, values: const {'n': '-5'});
      expect(negative.content, '-5小于零非正等于负五');

      final positive = _evaluate(content, values: const {'n': '7'});
      expect(positive.content, '7大于零非负不等于负五');

      final zero = _evaluate(content, values: const {'n': '0'});
      expect(zero.content, '0非负非正不等于负五');
    });

    test('按顺序选择首个成立分支，else if 与 else 兜底', () {
      const content =
          '{{x}}{{#if x == "a"}}A{{else if x == "b"}}B{{else}}C{{/if}}';

      expect(_evaluate(content, values: const {'x': 'a'}).content, 'aA');
      expect(_evaluate(content, values: const {'x': 'b'}).content, 'bB');
      expect(_evaluate(content, values: const {'x': 'z'}).content, 'zC');
    });

    test('多个分支条件同时成立时只渲染第一个分支', () {
      final result = _evaluate(
        '{{x}}{{#if x == "a"}}A{{else if x == "a"}}B{{/if}}',
        values: const {'x': 'a'},
      );
      expect(result.content, 'aA');
      expect(result.content, isNot(contains('B')));
    });

    test('无匹配且无 else 时条件块输出空', () {
      final result = _evaluate(
        '{{x}}{{#if x == "a"}}A{{/if}}',
        values: const {'x': 'z'},
      );
      expect(result.content, 'z');
    });
  });

  group('分支变量与活跃变量投影', () {
    test('活跃变量只含控制变量、顶层变量与选中分支变量且按声明顺序', () {
      const content =
          '{{阈值:number}}{{顶层}}{{开关:select|开|关}}'
          '{{#if 开关 == "开"}}{{分支甲}}{{else}}{{分支乙}}{{/if}}'
          '{{#if 阈值 >= 2}}多{{/if}}';
      const values = {'阈值': '3', '顶层': '顶', '开关': '开', '分支甲': '甲', '分支乙': '乙'};

      final on = _evaluate(content, values: values);
      expect(on.activeInputVariableNames, ['阈值', '顶层', '开关', '分支甲']);

      final off = _evaluate(
        content,
        values: const {'阈值': '3', '顶层': '顶', '开关': '关', '分支甲': '甲', '分支乙': '乙'},
      );
      expect(off.activeInputVariableNames, ['阈值', '顶层', '开关', '分支乙']);
    });

    test('隐藏分支中的变量值仍保留在 effectiveValues', () {
      final result = _evaluate(
        '{{开关:select|开|关}}{{#if 开关 == "开"}}{{分支甲}}{{/if}}',
        values: const {'开关': '关', '分支甲': '甲值'},
      );
      expect(result.effectiveValues, {'开关': '关', '分支甲': '甲值'});
      expect(result.activeInputVariableNames, ['开关']);
    });

    test('分支内普通变量占位符正常替换，不作为嵌套模板引用', () {
      final result = _evaluate(
        '{{x}}{{#if x == "a"}}主角是{{主角名}}。{{/if}}',
        values: const {'x': 'a', '主角名': '林昭'},
      );
      expect(result.content, 'a主角是林昭。');
      expect(result.activeInputVariableNames, ['x', '主角名']);
    });
  });

  group('有效值回落与草稿归一化', () {
    test('缺失或空输入回落已保存默认值', () {
      final prompt = TemplatePrompt(
        id: 't1',
        title: '模板',
        content:
            '{{语气}}{{章节:number}}{{人称:select|一|二|三}}{{#if 语气 == "专业"}}P{{/if}}',
        variables: const [
          TemplatePromptVariable(name: '语气', defaultValue: '专业'),
          TemplatePromptVariable(
            name: '章节',
            defaultValue: '3',
            type: TemplatePromptVariableType.number,
          ),
          TemplatePromptVariable(
            name: '人称',
            defaultValue: '二',
            type: TemplatePromptVariableType.select,
            options: ['一', '二', '三'],
          ),
        ],
        updatedAt: DateTime(2026),
      );
      final compilation = compileTemplatePromptDefinition(prompt);
      expect(compilation.isValid, isTrue);

      final evaluation = evaluateTemplatePrompt(
        program: compilation.program!,
        body: '内容',
        variableValues: const {'语气': '', '章节': '', '人称': ''},
      );
      expect(evaluation.isValid, isTrue);
      expect(evaluation.effectiveValues, {'语气': '专业', '章节': '3', '人称': '二'});
      expect(evaluation.content, '内容\n专业3二P');
    });

    test('normalizeTemplatePromptVariableDraftValue 空输入回落配置默认值', () {
      const variable = TemplatePromptVariable(
        name: '人称',
        defaultValue: '二',
        type: TemplatePromptVariableType.select,
        options: ['一', '二', '三'],
      );
      expect(normalizeTemplatePromptVariableDraftValue(variable, null), '二');
      expect(normalizeTemplatePromptVariableDraftValue(variable, ''), '二');
      expect(normalizeTemplatePromptVariableDraftValue(variable, '   '), '二');
    });

    test('normalizeTemplatePromptVariableDraftValue 陈旧 select 值回落配置默认值', () {
      const variable = TemplatePromptVariable(
        name: '人称',
        defaultValue: '二',
        type: TemplatePromptVariableType.select,
        options: ['一', '二', '三'],
      );
      expect(normalizeTemplatePromptVariableDraftValue(variable, '四'), '二');
      expect(normalizeTemplatePromptVariableDraftValue(variable, ' 四 '), '二');
      expect(normalizeTemplatePromptVariableDraftValue(variable, '三'), '三');
      expect(normalizeTemplatePromptVariableDraftValue(variable, ' 三 '), '三');
    });

    test('normalizeTemplatePromptVariableDraftValue 对文本与数字原样保留非空输入', () {
      const textVariable = TemplatePromptVariable(
        name: '语气',
        defaultValue: '专业',
      );
      expect(
        normalizeTemplatePromptVariableDraftValue(textVariable, ' 你好 '),
        '你好',
      );
      expect(normalizeTemplatePromptVariableDraftValue(textVariable, ''), '专业');

      const numberVariable = TemplatePromptVariable(
        name: '章节',
        defaultValue: '3',
        type: TemplatePromptVariableType.number,
      );
      expect(
        normalizeTemplatePromptVariableDraftValue(numberVariable, ' 5 '),
        '5',
      );
      expect(
        normalizeTemplatePromptVariableDraftValue(numberVariable, null),
        '3',
      );
    });

    test('变量有效值去除两端空白后与无空白字面量匹配', () {
      final result = _evaluate(
        '{{x}}{{#if x == "a"}}命中{{/if}}',
        values: const {'x': '  a  '},
      );
      expect(result.content, 'a命中');
    });

    test('变量有效值去空白与字面量保留内部空白导致不匹配', () {
      final result = _evaluate(
        '{{x}}{{#if x == " a "}}命中{{/if}}',
        values: const {'x': ' a '},
      );
      expect(result.content, 'a');
      expect(result.effectiveValues['x'], 'a');
    });
  });

  group('类型化值错误', () {
    test('非空非法数字产生 invalidNumber 值错误且不猜分支', () {
      final result = _evaluate(
        '{{n:number}}{{#if n >= 2}}多{{/if}}',
        values: const {'n': 'abc'},
      );
      expect(result.isValid, isFalse);
      expect(result.valueErrors.single.variableName, 'n');
      expect(
        result.valueErrors.single.code,
        TemplatePromptValueErrorCode.invalidNumber,
      );
      // 控制值无效时不猜分支，仍暴露控制字段供用户修复。
      expect(result.activeInputVariableNames, ['n']);
      expect(result.content, 'abc');
    });

    test('非空 select 值不在选项时产生 invalidSelectValue 且不猜分支', () {
      final result = _evaluate(
        '{{人称:select|一|二|三}}{{#if 人称 == "一"}}A{{/if}}',
        values: const {'人称': '四'},
      );
      expect(result.isValid, isFalse);
      expect(result.valueErrors.single.variableName, '人称');
      expect(
        result.valueErrors.single.code,
        TemplatePromptValueErrorCode.invalidSelectValue,
      );
      expect(result.activeInputVariableNames, ['人称']);
      expect(result.content, '四');
    });

    test('空输入数字回落默认值不报错，有效整数正常比较', () {
      final fallback = _evaluate(
        '{{n:number}}{{#if n >= 2}}多{{/if}}',
        values: const {'n': ''},
      );
      expect(fallback.isValid, isTrue);
      expect(fallback.content, '1');

      final valid = _evaluate(
        '{{n:number}}{{#if n >= 2}}多{{/if}}',
        values: const {'n': '3'},
      );
      expect(valid.isValid, isTrue);
      expect(valid.content, '3多');
    });
  });

  group('正文与输出片段', () {
    test('顶层正文生成正文 chunk 且保持位置', () {
      final result = _evaluate(
        '前置{{正文}}后置{{x}}',
        body: '内容',
        values: const {'x': 'X'},
      );
      expect(result.chunks, const [
        TemplatePromptOutputChunk(
          text: '前置',
          kind: TemplatePromptOutputChunkKind.template,
        ),
        TemplatePromptOutputChunk(
          text: '内容',
          kind: TemplatePromptOutputChunkKind.body,
        ),
        TemplatePromptOutputChunk(
          text: '后置X',
          kind: TemplatePromptOutputChunkKind.template,
        ),
      ]);
      expect(result.content, '前置内容后置X');
    });

    test('相邻同 kind 片段合并为一个 chunk', () {
      final result = _evaluate(
        '{{x}}{{y}}尾',
        values: const {'x': 'a', 'y': 'b'},
      );
      expect(result.chunks, const [
        TemplatePromptOutputChunk(
          text: 'ab尾',
          kind: TemplatePromptOutputChunkKind.template,
        ),
      ]);
    });

    test('无正文占位符时非空正文与换行前置', () {
      final result = _evaluate('{{x}}后置', body: '内容', values: const {'x': 'X'});
      expect(result.chunks, const [
        TemplatePromptOutputChunk(
          text: '内容\n',
          kind: TemplatePromptOutputChunkKind.body,
        ),
        TemplatePromptOutputChunk(
          text: 'X后置',
          kind: TemplatePromptOutputChunkKind.template,
        ),
      ]);
      expect(result.content, '内容\nX后置');
    });

    test('正文为空或模板内容为空时不前置额外换行', () {
      final emptyBody = _evaluate(
        '{{x}}后置',
        body: '',
        values: const {'x': 'X'},
      );
      expect(emptyBody.content, 'X后置');
      expect(emptyBody.chunks, const [
        TemplatePromptOutputChunk(
          text: 'X后置',
          kind: TemplatePromptOutputChunkKind.template,
        ),
      ]);

      final emptyTemplate = _evaluate(
        '{{x}}',
        body: '内容',
        values: const {'x': ''},
      );
      expect(emptyTemplate.content, '内容');
      expect(emptyTemplate.chunks, const [
        TemplatePromptOutputChunk(
          text: '内容',
          kind: TemplatePromptOutputChunkKind.body,
        ),
      ]);
    });
  });

  group('控制标签与空白', () {
    test('inline 控制标签保留作者书写的外围空白', () {
      final compilation = compileTemplatePromptContent(
        '视角：{{人称:select|一|三}}{{#if 人称 == "一"}}用第一人称{{else}}用第三人称{{/if}}撰写。',
      );
      expect(compilation.isValid, isTrue);

      final on = evaluateTemplatePrompt(
        program: compilation.program!,
        body: '',
        variableValues: const {'人称': '一'},
      );
      expect(on.content, '视角：一用第一人称撰写。');

      final off = evaluateTemplatePrompt(
        program: compilation.program!,
        body: '',
        variableValues: const {'人称': '三'},
      );
      expect(off.content, '视角：三用第三人称撰写。');

      final spaced = _evaluate(
        '{{x}}开始{{#if x == "a"}}A{{/if}} 结束',
        values: const {'x': 'a'},
      );
      expect(spaced.content, 'a开始A 结束');
    });

    test('独占控制行删除缩进但保留分支正文缩进', () {
      final compilation = compileTemplatePromptContent(
        '视角：{{人称:select|一|三}}\n要求：\n  {{#if 人称 == "一"}}\n  第一人称。\n  {{/if}}\n{{正文}}',
      );
      final evaluation = evaluateTemplatePrompt(
        program: compilation.program!,
        body: '内容',
        variableValues: const {'人称': '一'},
      );

      expect(evaluation.content, '视角：一\n要求：\n  第一人称。\n内容');
    });

    test('无缩进的独占行控制标签连同行尾一起裁剪', () {
      final result = _evaluate(
        '{{人称:select|一|三}}写作要求：\n{{#if 人称 == "一"}}\n使用第一人称。\n{{/if}}\n正文如下：\n{{正文}}',
        body: '内容',
        values: const {'人称': '一'},
      );
      expect(result.content, '一写作要求：\n使用第一人称。\n正文如下：\n内容');
    });
  });
}
