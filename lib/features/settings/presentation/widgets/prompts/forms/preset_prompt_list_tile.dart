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
              : Colors.transparent,
          shape: Border(
            left: BorderSide(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: InkWell(
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
