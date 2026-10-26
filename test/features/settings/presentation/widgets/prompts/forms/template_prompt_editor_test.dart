import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart'
    show TemplatePrompt, TemplatePromptVariable, TemplatePromptVariableType;
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_editor.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/memory_prompt_editor.dart';

void main() {
  testWidgets('只修改变量默认值也拦截返回，恢复原值后放行', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TemplatePromptEditor(
          initialValue: TemplatePrompt(
            id: 'template',
            title: '称呼模板',
            content: '{{称呼}}',
            variables: const [
              TemplatePromptVariable(name: '称呼', defaultValue: '原称呼'),
            ],
            updatedAt: DateTime(2026),
          ),
          onSubmit: (_) async {},
        ),
      ),
    );
    final route = ModalRoute.of(
      tester.element(find.byType(TemplatePromptEditor)),
    )!;
    expect(route.popDisposition, RoutePopDisposition.bubble);
    final field = find.widgetWithText(AppTextField, '称呼');
    await tester.enterText(field, '新称呼');
    await tester.pump();
    expect(route.popDisposition, RoutePopDisposition.doNotPop);
    await tester.enterText(field, '原称呼');
    await tester.pump();
    expect(route.popDisposition, RoutePopDisposition.bubble);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Future<void> Function(TemplatePromptFormData) onSubmit,
  }) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: TemplatePromptEditor(onSubmit: onSubmit)),
    );
  }

  Finder titleField() => find.descendant(
    of: find.byType(TemplatePromptEditor),
    matching: find.widgetWithText(AppTextField, '标题'),
  );

  Finder contentField() => find.descendant(
    of: find.byType(TemplatePromptEditor),
    matching: find.widgetWithText(AppTextField, '模板提示词'),
  );

  /// 文本变量默认值输入框（label 即变量名）。
  Finder textVariableField(String name) => find.descendant(
    of: find.byType(TemplatePromptEditor),
    matching: find.widgetWithText(AppTextField, name),
  );

  /// 单选变量默认值下拉框（DropdownButtonFormField 非 TextFormField，
  /// 需按泛型控件与 label 定位）。
  Finder selectVariableField(String name) => find.descendant(
    of: find.byType(TemplatePromptEditor),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AppDropdownField<String> &&
          widget.decoration.labelText == '$name（单选）',
    ),
  );

  /// 输入模板正文并精确推进防抖常量，触发变量重算。
  Future<void> typeContent(WidgetTester tester, String content) async {
    await tester.enterText(contentField(), content);
    await tester.pump(TemplatePromptEditor.variableReconcileDebounce);
    await tester.pump();
  }

  group('模板提示词表单', () {
    for (final isTemplate in [true, false]) {
      testWidgets('${isTemplate ? '模板' : '记忆'}提示词在键盘展开和收起后保持焦点与组合输入', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: isTemplate
                ? TemplatePromptEditor(onSubmit: (_) async {})
                : MemoryPromptEditor(onSubmit: (_) async {}),
          ),
        );
        final field = find.widgetWithText(
          AppTextField,
          isTemplate ? '模板提示词' : '记忆总结提示词',
        );
        await tester.showKeyboard(field);
        final content = List.generate(40, (i) => '第 $i 行正文').join('\n');
        final value = TextEditingValue(
          text: content,
          selection: TextSelection.collapsed(offset: content.length),
          composing: TextRange(start: content.length - 2, end: content.length),
        );
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        addTearDown(tester.view.resetViewInsets);
        final originalState = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        for (final bottom in [420.0, 540.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: bottom);
          await tester.pumpAndSettle();
          final editable = tester.widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(editable.controller.value, value);
          expect(
            tester.state<EditableTextState>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            ),
            same(originalState),
          );
          expect(find.text('保存').hitTestable(), findsOneWidget);
          final render = originalState.renderEditable;
          final caret = render.getLocalRectForCaret(value.selection.extent);
          expect(
            render.localToGlobal(caret.bottomRight).dy,
            lessThan(844 - bottom),
          );
          expect(render.localToGlobal(caret.topLeft).dy, greaterThan(56));
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('选择单选默认值后提交返回 select 类型变量及其选项', (tester) async {
      TemplatePromptFormData? captured;
      await pumpEditor(
        tester,
        onSubmit: (data) async {
          captured = data;
        },
      );

      await typeContent(tester, '{{人称:select|一|二|三}}');
      await tester.enterText(titleField(), '人称模板');

      // 打开下拉菜单并选择“二”（菜单项渲染在 Overlay 中）。
      await tester.tap(selectVariableField('人称'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('二').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

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
      await pumpEditor(
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

    testWidgets('正文防抖协调变量，无效内容保留默认值，修复后可保存', (tester) async {
      TemplatePromptFormData? saved;
      await pumpEditor(
        tester,
        onSubmit: (data) async {
          saved = data;
        },
      );
      await tester.enterText(titleField(), '防抖模板');

      await tester.enterText(contentField(), '请处理{{变量A}}。');
      await tester.pump();
      expect(find.text('变量A'), findsNothing);
      await tester.pump(TemplatePromptEditor.variableReconcileDebounce);
      await tester.pump();
      expect(find.text('变量A'), findsOneWidget);
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
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(saved, isNull);
      await typeContent(tester, '请处理{{变量A}}。');
      expect(find.text('第 1 行第 12 列：控制标签未闭合，缺少 }}'), findsNothing);
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('旧值'), findsOneWidget);
      await tester.enterText(contentField(), '请处理{{变量B}}。');
      await tester.pump();
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('变量B'), findsNothing);
      await tester.pump(TemplatePromptEditor.variableReconcileDebounce);
      await tester.pump();
      expect(find.text('变量A'), findsNothing);
      expect(find.text('变量B'), findsOneWidget);
      await tester.enterText(textVariableField('变量B'), '新值');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved!.variables.single.name, '变量B');
      expect(saved!.variables.single.defaultValue, '新值');
    });
  });
}
