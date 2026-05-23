import 'package:flutter/material.dart';

import '../../../../settings/domain/models/template_prompt.dart';

class ComposerTemplateHeader extends StatelessWidget {
  const ComposerTemplateHeader({
    required this.selectedTemplatePrompt,
    required this.templatePrompts,
    required this.isBusy,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    super.key,
  });

  final TemplatePrompt? selectedTemplatePrompt;
  final List<TemplatePrompt> templatePrompts;
  final bool isBusy;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('template-prompt-selector'),
            initialValue: selectedTemplatePrompt?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '模板提示词'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('不使用模板提示词'),
              ),
              ...templatePrompts.map((templatePrompt) {
                return DropdownMenuItem<String?>(
                  value: templatePrompt.id,
                  child: Text(templatePrompt.title),
                );
              }),
            ],
            onChanged: isBusy ? null : onTemplatePromptSelected,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.outlined(
          onPressed: onToggleComposerCollapsed,
          tooltip: '收起输入区',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      ],
    );
  }
}
