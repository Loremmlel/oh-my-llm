import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

/// 单选变量下拉框。
///
/// 受控于既有 [TextEditingController]：选中值永远来自 `controller.text`，
/// `onChanged` 只把选项字符串写进 controller，绝不把索引放进任何状态。
/// 选项按声明原样渲染，显示文本与插入模板的值相同。
class SelectVariableField extends StatelessWidget {
  const SelectVariableField({
    required this.controller,
    required this.variable,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final TemplatePromptVariable variable;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return AppDropdownField<String>(
      key: ValueKey(controller.text),
      initialValue: controller.text,
      decoration: InputDecoration(
        labelText: variable.name,
        errorText: errorText,
      ),
      items: [
        for (final option in variable.options)
          DropdownMenuItem<String>(value: option, child: Text(option)),
      ],
      onChanged: (value) {
        if (value == null) {
          return;
        }
        controller.text = value;
      },
    );
  }
}
