import 'package:flutter/material.dart';

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
    return InputDecorator(
      decoration: InputDecoration(
        labelText: variable.name,
        errorText: errorText,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          // 控制器在字段绑定阶段已按当前选项归一化，controller.text 必是有效选项。
          value: controller.text,
          isExpanded: true,
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
        ),
      ),
    );
  }
}
