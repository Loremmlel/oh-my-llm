import 'package:flutter/material.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_evaluator.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';
import 'number_variable_field.dart';
import 'select_variable_field.dart';

/// 模板变量字段区：按 [program] 声明顺序渲染活跃变量。
///
/// 只渲染 [activeInputVariableNames] 中的变量（控制变量 + 当前有效分支）；
/// 隐藏分支的控制器由 [ChatScreen] 保留，不在此处删除或重建，切回分支时
/// 草稿值不丢失。值错误按变量名附着到对应字段。
class ComposerTemplateVariableFields extends StatelessWidget {
  const ComposerTemplateVariableFields({
    required this.program,
    required this.activeInputVariableNames,
    required this.templateVariableControllers,
    required this.valueErrorsByVariable,
    super.key,
  });

  final TemplatePromptProgram program;
  final Set<String> activeInputVariableNames;
  final Map<String, TextEditingController> templateVariableControllers;
  final Map<String, TemplatePromptValueError> valueErrorsByVariable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 220.0;
        const gap = 6.0;
        final crossAxisCount =
            ((constraints.maxWidth + gap) / (minItemWidth + gap)).floor().clamp(
              1,
              3,
            );
        final itemWidth = crossAxisCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (crossAxisCount - 1)) /
                  crossAxisCount;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final variable in program.inputVariables)
              if (activeInputVariableNames.contains(variable.name))
                switch (variable.type) {
                  TemplatePromptVariableType.number => NumberVariableField(
                    key: ValueKey('number-variable-${variable.name}'),
                    controller: templateVariableControllers[variable.name]!,
                    labelText: variable.name,
                    errorText: valueErrorsByVariable[variable.name]?.message,
                  ),
                  TemplatePromptVariableType.select => SizedBox(
                    width: itemWidth,
                    child: SelectVariableField(
                      key: ValueKey('select-variable-${variable.name}'),
                      controller: templateVariableControllers[variable.name]!,
                      variable: variable,
                      errorText: valueErrorsByVariable[variable.name]?.message,
                    ),
                  ),
                  TemplatePromptVariableType.text => SizedBox(
                    width: itemWidth,
                    child: TextField(
                      key: ValueKey('template-variable-${variable.name}'),
                      controller: templateVariableControllers[variable.name]!,
                      decoration: InputDecoration(
                        labelText: variable.name,
                        hintText: variable.defaultValue.isEmpty
                            ? '未设置默认值'
                            : variable.defaultValue,
                      ),
                    ),
                  ),
                },
          ],
        );
      },
    );
  }
}
