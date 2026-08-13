import 'package:flutter/material.dart';

import 'editable_preset_prompt_item.dart';

/// 左侧的预设 Prompt 标题项。
class PresetPromptListTile extends StatelessWidget {
  const PresetPromptListTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final EditablePresetPromptItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: item.titleController,
      builder: (context, child) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Material(
          color: isSelected
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                item.titleController.text.trim().isEmpty
                    ? '未命名条目'
                    : item.titleController.text.trim(),
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}
