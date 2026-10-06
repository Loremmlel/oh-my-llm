import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import '../../../../domain/models/prompts/preset_prompt.dart';
import 'preset_prompt_editor_role.dart';

/// 表单内使用的可编辑预设 Prompt 条目。
class EditablePresetPromptItem {
  const EditablePresetPromptItem({
    required this.id,
    required this.role,
    required this.titleController,
    required this.contentController,
    this.placement,
  });

  final String id;
  final PresetPromptEditorRole role;
  final PromptMessagePlacement? placement;
  final TextEditingController titleController;
  final LongTextEditingController contentController;

  EditablePresetPromptItem copyWith({
    String? id,
    PresetPromptEditorRole? role,
    PromptMessagePlacement? placement,
    TextEditingController? titleController,
    LongTextEditingController? contentController,
  }) {
    return EditablePresetPromptItem(
      id: id ?? this.id,
      role: role ?? this.role,
      placement: placement ?? this.placement,
      titleController: titleController ?? this.titleController,
      contentController: contentController ?? this.contentController,
    );
  }
}
