import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart'
    show TemplatePromptVariableType;
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
  }) async {
    final sp = await SharedPreferences.getInstance();
    await pumpTestApp(
      tester,
      preferences: sp,
      child: Scaffold(
        body: Center(child: TemplatePromptFormDialog(onSubmit: onSubmit)),
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

  group('模板提示词表单', () {
    testWidgets('语法说明默认收起且可展开', (tester) async {
      await pumpDialog(tester, onSubmit: (_) async {});

      expect(find.text('模板语法说明'), findsOneWidget);
      expect(find.text('{{主角名}}'), findsNothing);

      await expandSyntaxHelp(tester);

      expect(find.text('{{主角名}}'), findsOneWidget);
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
  });
}
