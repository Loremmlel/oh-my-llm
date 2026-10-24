import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import '../../../../domain/models/prompts/memory_prompt.dart';
import '../../shared/settings_editor_list.dart';
import '../../shared/settings_form_dialog_state_mixin.dart';

/// 记忆总结提示词表单提交数据。
class MemoryPromptFormData {
  const MemoryPromptFormData({required this.name, required this.content});

  final String name;
  final String content;
}

/// 新增或编辑记忆总结提示词的页面工作区。
class MemoryPromptEditor extends StatefulWidget {
  const MemoryPromptEditor({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(MemoryPromptFormData formData) onSubmit;
  final MemoryPrompt? initialValue;

  @override
  State<MemoryPromptEditor> createState() => _MemoryPromptEditorState();
}

class _MemoryPromptEditorState extends State<MemoryPromptEditor>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _name = initController(
    widget.initialValue?.name ?? '',
  );
  late final LongTextEditingController _content = initLongTextController(
    widget.initialValue?.content ?? '',
  );

  String _snapshot() => jsonEncode([_name.text, _content.text]);

  @override
  void initState() {
    super.initState();
    captureInitialSnapshot(_snapshot());
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildEditorPage(
    title: widget.initialValue == null ? '新增记忆总结提示词' : '编辑记忆总结提示词',
    targetName: '记忆总结提示词',
    helpText: '配置聊天页创建检查点时可选择的总结提示词，用于适配不同场景下的记忆沉淀方式。',
    snapshotBuilder: _snapshot,
    shouldScrollContent: (constraints) => constraints.maxHeight < 240,
    onSubmit: () async {
      if (!validateForm()) return;
      await submitPageAndClose(
        () => widget.onSubmit(
          MemoryPromptFormData(
            name: _name.text.trim(),
            content: _content.textForSave(trim: true),
          ),
        ),
      );
    },
    builder: (_, constraints, _) {
      final expand = constraints.hasBoundedHeight;
      return Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField.form(
            controller: _name,
            readOnly: isSaving,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：研发任务总结 / 写作人设总结',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 12),
          SettingsExpandedTextField(
            controller: _content,
            expand: expand,
            readOnly: isSaving,
            validator: validateRequired,
            decoration: const InputDecoration(
              labelText: '记忆总结提示词',
              hintText: '说明你希望模型如何总结当前上下文，例如保留哪些重点、输出什么结构。',
              alignLabelWithHint: true,
            ),
          ),
        ],
      );
    },
  );
}
