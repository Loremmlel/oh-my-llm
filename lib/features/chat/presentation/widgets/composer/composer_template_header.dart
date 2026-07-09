import 'package:flutter/material.dart';

import '../../../../settings/domain/models/template_prompt.dart';

class ComposerTemplateHeader extends StatelessWidget {
  const ComposerTemplateHeader({
    required this.selectedTemplatePrompt,
    required this.templatePrompts,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    super.key,
  });

  final TemplatePrompt? selectedTemplatePrompt;
  final List<TemplatePrompt> templatePrompts;
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
            // 流式期间切换模板不影响进行中的请求，仅作用于下次发送。
            onChanged: onTemplatePromptSelected,
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
