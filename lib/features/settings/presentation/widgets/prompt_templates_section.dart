import 'package:flutter/material.dart';

import '../../domain/models/prompt_template.dart';
import 'prompt_templates_list.dart';
import 'settings_section_card.dart';

/// 设置页中的预设 Prompt 分区。
class PromptTemplatesSection extends StatelessWidget {
  const PromptTemplatesSection({
    required this.templates,
    required this.onAddPressed,
    required this.onEditRequested,
    super.key,
  });

  final List<PromptTemplate> templates;
  final VoidCallback onAddPressed;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '预设 Prompt',
      description: '配置可在聊天页选择的预设 Prompt，支持 system、前置与后置上下文，并记住最近一次使用的选择。',
      action: FilledButton.icon(
        onPressed: onAddPressed,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增预设'),
      ),
      child: PromptTemplatesList(
        templates: templates,
        onEditRequested: onEditRequested,
      ),
    );
  }
}
