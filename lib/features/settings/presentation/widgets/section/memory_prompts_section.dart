import 'package:flutter/material.dart';

import '../../../domain/models/memory_prompt.dart';
import '../list/memory_prompts_list.dart';
import '../settings_section_card.dart';

/// 设置页中的记忆总结提示词分区。
class MemoryPromptsSection extends StatelessWidget {
  const MemoryPromptsSection({
    required this.memoryPrompts,
    required this.onAddPressed,
    required this.onEditRequested,
    super.key,
  });

  final List<MemoryPrompt> memoryPrompts;
  final VoidCallback onAddPressed;
  final ValueChanged<MemoryPrompt> onEditRequested;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '记忆总结提示词',
      description: '配置聊天页创建检查点时可选择的总结提示词，用于适配不同场景下的记忆沉淀方式。',
      action: FilledButton.icon(
        onPressed: onAddPressed,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增记忆提示词'),
      ),
      child: MemoryPromptsList(
        memoryPrompts: memoryPrompts,
        onEditRequested: onEditRequested,
      ),
    );
  }
}
