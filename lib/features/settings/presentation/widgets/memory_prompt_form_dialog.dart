import 'package:flutter/material.dart';

import '../../domain/models/memory_prompt.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

/// 记忆总结提示词表单提交数据。
class MemoryPromptFormData {
  const MemoryPromptFormData({required this.name, required this.content});

  final String name;
  final String content;
}

/// 新增或编辑记忆总结提示词的对话框。
class MemoryPromptFormDialog extends StatefulWidget {
  const MemoryPromptFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(MemoryPromptFormData formData) onSubmit;
  final MemoryPrompt? initialValue;

  @override
  State<MemoryPromptFormDialog> createState() => _MemoryPromptFormDialogState();
}

class _MemoryPromptFormDialogState extends State<MemoryPromptFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialValue?.content ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑记忆总结提示词' : '新增记忆总结提示词',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：研发任务总结 / 写作人设总结',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contentController,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '记忆总结提示词',
              hintText: '说明你希望模型如何总结当前上下文，例如保留哪些重点、输出什么结构。',
              alignLabelWithHint: true,
            ),
            validator: validateRequired,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!validateForm()) {
      return;
    }

    await submitAndClose(() {
      return widget.onSubmit(
        MemoryPromptFormData(
          name: _nameController.text.trim(),
          content: _contentController.text.trim(),
        ),
      );
    });
  }
}
