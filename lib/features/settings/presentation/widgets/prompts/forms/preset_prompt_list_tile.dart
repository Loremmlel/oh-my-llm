import 'package:flutter/material.dart';

import '../../shared/settings_editor_list.dart';
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: item.titleController,
      builder: (context, child) => SettingsEditorListTile(
        title: item.titleController.text,
        selected: isSelected,
        onTap: onTap,
      ),
    );
  }
}
