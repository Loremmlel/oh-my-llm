import 'package:flutter/material.dart';

import '../../../domain/models/preset_prompt.dart';
import '../list/preset_prompts_list.dart';
import '../settings_section_card.dart';

/// 设置页中的预设 Prompt 分区。
class PresetPromptsSection extends StatelessWidget {
  const PresetPromptsSection({
    required this.templates,
    required this.onAddPressed,
    required this.onDuplicateRequested,
    required this.onEditRequested,
    super.key,
  });

  final List<PresetPrompt> templates;
  final VoidCallback onAddPressed;
  final Future<void> Function(PresetPrompt template) onDuplicateRequested;
  final ValueChanged<PresetPrompt> onEditRequested;

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
      child: PresetPromptsList(
        templates: templates,
        onDuplicateRequested: onDuplicateRequested,
        onEditRequested: onEditRequested,
      ),
    );
  }
}
