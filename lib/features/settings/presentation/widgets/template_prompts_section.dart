import 'package:flutter/material.dart';

import '../../domain/models/template_prompt.dart';
import 'settings_section_card.dart';
import 'template_prompts_list.dart';

/// 设置页中的模板提示词分区。
class TemplatePromptsSection extends StatelessWidget {
  const TemplatePromptsSection({
    required this.templatePrompts,
    required this.onAddPressed,
    required this.onEditRequested,
    super.key,
  });

  final List<TemplatePrompt> templatePrompts;
  final VoidCallback onAddPressed;
  final ValueChanged<TemplatePrompt> onEditRequested;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '模板提示词',
      description: '配置可在聊天页临时应用的变量模板。使用 {{变量名}} 声明注入位，{{正文}} 对应主输入框。',
      action: FilledButton.icon(
        onPressed: onAddPressed,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增模板提示词'),
      ),
      child: TemplatePromptsList(
        templatePrompts: templatePrompts,
        onEditRequested: onEditRequested,
      ),
    );
  }
}
