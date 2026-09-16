import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

class ComposerTemplateHeader extends StatelessWidget {
  const ComposerTemplateHeader({
    required this.selectedTemplatePrompt,
    required this.templatePrompts,
    required this.onTemplatePromptSelected,
    super.key,
  });

  final TemplatePrompt? selectedTemplatePrompt;
  final List<TemplatePrompt> templatePrompts;
  final ValueChanged<String?> onTemplatePromptSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      key: const ValueKey('template-prompt-selector'),
      initialValue: selectedTemplatePrompt?.id,
      isExpanded: true,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      decoration: const InputDecoration(labelText: '模板提示词'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('不使用模板提示词')),
        ...templatePrompts.map((templatePrompt) {
          return DropdownMenuItem<String?>(
            value: templatePrompt.id,
            child: Text(templatePrompt.title, overflow: TextOverflow.ellipsis),
          );
        }),
      ],
      // 流式期间切换模板不影响进行中的请求，仅作用于下次发送。
      onChanged: onTemplatePromptSelected,
    );
  }
}
