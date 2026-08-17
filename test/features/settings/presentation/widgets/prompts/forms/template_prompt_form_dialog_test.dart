import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart';

import '../../../../../../helpers/test_harness.dart';
import '../../../../../../helpers/async/widget_test_animation.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<void> Function(TemplatePromptFormData) onSubmit,
    TemplatePrompt? initialValue,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await pumpTestApp(
      tester,
      preferences: sp,
      child: Scaffold(
        body: Center(
          child: TemplatePromptFormDialog(
            onSubmit: onSubmit,
            initialValue: initialValue,
          ),
        ),
      ),
    );
  }

  Finder titleField() => find.descendant(
    of: find.byType(TemplatePromptFormDialog),
    matching: find.widgetWithText(TextFormField, '标题'),
  );

  Finder contentField() => find.descendant(
    of: find.byType(TemplatePromptFormDialog),
    matching: find.widgetWithText(TextFormField, '模板提示词'),
  );

  /// 文本变量默认值输入框（label 即变量名）。
  Finder textVariableField(String name) => find.descendant(
    of: find.byType(TemplatePromptFormDialog),
    matching: find.widgetWithText(TextFormField, name),
  );

  /// 数字变量默认值输入框（label 为「变量名（数字）」）。
  Finder numberVariableField(String name) => find.descendant(
    of: find.byType(TemplatePromptFormDialog),
    matching: find.widgetWithText(TextFormField, '$name（数字）'),
  );

  /// 单选变量默认值下拉框（DropdownButtonFormField 非 TextFormField，
  /// 需按泛型控件与 label 定位）。
  Finder selectVariableField(String name) => find.descendant(
    of: find.byType(TemplatePromptFormDialog),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == '$name（单选）',
    ),
  );

  /// 输入模板正文并精确推进防抖常量，触发变量重算。
  Future<void> typeContent(WidgetTester tester, String content) async {
    await tester.enterText(contentField(), content);
    await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce);
    await tester.pump();
  }

  /// 展开默认收起的语法说明区（有限展开动画）。
  Future<void> expandSyntaxHelp(WidgetTester tester) async {
    await tester.tap(find.text('模板语法说明'));
    await settleAnimatedWidgetTransition(tester);
  }

  /// 读取单选下拉框当前的选中值（闭合状态下 IndexedStack 会保留全部选项
  /// 文本，可见文本断言无法区分选中项，故读取 FormField 的值）。
  String? selectedSelectValue(WidgetTester tester, String name) {
    return tester
        .state<FormFieldState<String>>(selectVariableField(name))
        .value;
  }

  group('TemplatePromptFormDialog', () {
    testWidgets('语法说明默认收起，展开后展示文本/数字/单选/条件/正文示例', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      expect(find.text('模板语法说明'), findsOneWidget);
      expect(find.text('{{主角名}}'), findsNothing);

      await expandSyntaxHelp(tester);

      expect(find.text('{{主角名}}'), findsOneWidget);
      expect(find.text('{{章节数:number}}'), findsOneWidget);
      expect(find.text('{{人称:select|一|二|三}}'), findsOneWidget);
      expect(find.text('{{#if 人称 == "一"}}'), findsOneWidget);
      expect(find.text('{{else if 人称 == "二"}}'), findsOneWidget);
      expect(find.text('{{else}}'), findsOneWidget);
      expect(find.text('{{/if}}'), findsOneWidget);
      expect(find.textContaining('{{正文}} 必须放在条件块之外'), findsOneWidget);
    });

    testWidgets('语法说明明确第一版限制：嵌套条件、选项内 | 与 {{ 转义均不支持', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});
      await expandSyntaxHelp(tester);

      expect(find.textContaining('不支持嵌套条件'), findsOneWidget);
      expect(find.textContaining('不支持在单选选项中使用 |'), findsOneWidget);
      expect(find.textContaining('{{ 转义为字面文本'), findsOneWidget);
    });

    testWidgets('输入单选变量声明后默认下拉框选中首个选项', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      await typeContent(tester, '请选择{{人称:select|一|二|三}}。');

      expect(selectVariableField('人称'), findsOneWidget);
      expect(selectedSelectValue(tester, '人称'), '一');
    });

    testWidgets('选择单选默认值后提交返回 select 类型变量及其选项', (tester) async {
      TemplatePromptFormData? captured;
      await pumpDialog(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
      );

      await typeContent(tester, '{{人称:select|一|二|三}}');
      await tester.enterText(titleField(), '人称模板');

      // 打开下拉菜单并选择“二”（菜单项渲染在 Overlay 中）。
      await tester.tap(selectVariableField('人称'));
      await settleOverlayTransition(tester);
      await tester.tap(find.text('二').last);
      await settleOverlayTransition(tester);

      expect(selectedSelectValue(tester, '人称'), '二');

      await tester.tap(find.text('保存'));
      await settleOverlayTransition(tester);

      expect(captured, isNotNull);
      final selectVariable = captured!.variables.singleWhere(
        (variable) => variable.name == '人称',
      );
      expect(selectVariable.type, TemplatePromptVariableType.select);
      expect(selectVariable.options, ['一', '二', '三']);
      expect(selectVariable.defaultValue, '二');
    });

    testWidgets('编辑无关正文保留已有有效的单选默认值', (tester) async {
      await pumpDialog(
        tester,
        onSubmit: (_) async {},
        initialValue: TemplatePrompt(
          id: 't1',
          title: '人称模板',
          content: '{{人称:select|一|二|三}}',
          variables: const [
            TemplatePromptVariable(
              name: '人称',
              defaultValue: '二',
              type: TemplatePromptVariableType.select,
              options: ['一', '二', '三'],
            ),
          ],
          updatedAt: DateTime(2026),
        ),
      );

      expect(selectedSelectValue(tester, '人称'), '二');

      // 修改正文但不动选项声明，协调后默认值仍保留。
      await typeContent(tester, '请选择{{人称:select|一|二|三}}。');

      expect(selectedSelectValue(tester, '人称'), '二');
    });

    testWidgets('选项变化后默认值被移除时回落到首个选项（仅创作表单）', (tester) async {
      await pumpDialog(
        tester,
        onSubmit: (_) async {},
        initialValue: TemplatePrompt(
          id: 't1',
          title: '人称模板',
          content: '{{人称:select|一|二|三}}',
          variables: const [
            TemplatePromptVariable(
              name: '人称',
              defaultValue: '二',
              type: TemplatePromptVariableType.select,
              options: ['一', '二', '三'],
            ),
          ],
          updatedAt: DateTime(2026),
        ),
      );

      expect(selectedSelectValue(tester, '人称'), '二');

      await typeContent(tester, '{{人称:select|一|三}}');

      expect(selectedSelectValue(tester, '人称'), '一');
    });

    testWidgets('无效/未闭合/嵌套条件块展示首个带行列的诊断且不触发保存', (tester) async {
      TemplatePromptFormData? captured;
      await pumpDialog(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
      );
      await tester.enterText(titleField(), '无效模板');

      const cases = <(String, String)>[
        ('{{#if 人称 == "一"}}\n未闭合', '第 1 行第 1 列：缺少与 {{#if}} 对应的 {{/if}}'),
        (
          '{{a}}\n{{#if a == "1"}}\n{{#if a == "1"}}\n{{/if}}\n{{/if}}',
          '第 3 行第 1 列：条件块内不允许嵌套 {{#if}}',
        ),
      ];
      for (final (content, diagnostic) in cases) {
        await typeContent(tester, content);
        expect(find.text(diagnostic), findsOneWidget, reason: content);
        await tester.tap(find.text('保存'));
        await tester.pump();
      }
      expect(captured, isNull);
    });

    testWidgets('内容暂时无效时保留变量默认值控制器，修复后恢复协调', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      await typeContent(tester, '请处理{{变量A}}。');
      await tester.enterText(textVariableField('变量A'), '旧值');
      await tester.pump();
      expect(find.text('旧值'), findsOneWidget);

      // 变成无效内容：末尾出现未闭合的控制标签。
      await typeContent(tester, '请处理{{变量A}}。{{#if');

      // 诊断出现，但变量默认值输入框及其值不被清除。
      expect(find.text('第 1 行第 12 列：控制标签未闭合，缺少 }}'), findsOneWidget);
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('旧值'), findsOneWidget);

      // 修复内容后协调恢复，旧值仍在。
      await typeContent(tester, '请处理{{变量A}}。');
      expect(find.text('第 1 行第 12 列：控制标签未闭合，缺少 }}'), findsNothing);
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('旧值'), findsOneWidget);
    });

    testWidgets('分支内 {{正文}} 被拒绝，顶层正文变量保留不可编辑提示', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      // 分支内使用 {{正文}}：给出带行列的诊断。
      await typeContent(tester, '{{人称}}\n{{#if 人称 == "一"}}\n{{正文}}\n{{/if}}');
      expect(find.text('第 3 行第 1 列：{{正文}} 只能出现在条件块之外'), findsOneWidget);

      // 顶层 {{正文}}：显示不可编辑提示，不提供默认值输入框。
      await typeContent(tester, '{{正文}}请处理。');
      expect(find.textContaining('使用聊天页主输入框提供内容'), findsOneWidget);
      expect(textVariableField('正文'), findsNothing);
    });

    testWidgets('非法数字默认值触发字段级校验错误且不提交', (tester) async {
      TemplatePromptFormData? captured;
      await pumpDialog(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
      );

      await typeContent(tester, '从{{起始:number}}开始。');
      await tester.enterText(titleField(), '数字模板');
      await tester.enterText(numberVariableField('起始'), 'abc');
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('默认值需为整数'), findsOneWidget);
      expect(captured, isNull);
    });

    testWidgets('表单不提供预览标题或预览输出', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      await typeContent(tester, '{{主角名}}，你好。');
      await expandSyntaxHelp(tester);

      expect(find.text('预览'), findsNothing);
      expect(find.text('模板预览'), findsNothing);
      // “渲染预览”只出现在限制说明里，而不是独立的预览区域。
      expect(find.textContaining('渲染预览'), findsOneWidget);
    });
  });
}
