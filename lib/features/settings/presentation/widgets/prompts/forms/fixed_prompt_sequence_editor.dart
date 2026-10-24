import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';

import '../../../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../shared/settings_editor_list.dart';
import '../../shared/settings_form_dialog_state_mixin.dart';

/// 固定顺序提示词表单提交数据。
class FixedPromptSequenceFormData {
  const FixedPromptSequenceFormData({required this.name, required this.steps});

  final String name;
  final List<FixedPromptSequenceStep> steps;
}

/// 新增或编辑固定顺序提示词序列的页面工作区。
class FixedPromptSequenceEditor extends StatefulWidget {
  const FixedPromptSequenceEditor({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(FixedPromptSequenceFormData formData) onSubmit;
  final FixedPromptSequence? initialValue;

  @override
  State<FixedPromptSequenceEditor> createState() =>
      _FixedPromptSequenceEditorState();
}

class _FixedPromptSequenceEditorState extends State<FixedPromptSequenceEditor>
    with
        SettingsFormDialogStateMixin,
        SettingsItemListEditorMixin<
          FixedPromptSequenceEditor,
          FixedPromptSequenceStep
        > {
  @override
  String get initialName => widget.initialValue?.name ?? '';

  @override
  String get emptyItemTitle => '未命名步骤';

  @override
  String itemIdOf(FixedPromptSequenceStep item) => item.id;

  @override
  String itemTitleOf(FixedPromptSequenceStep item) => item.title;

  @override
  String itemContentOf(FixedPromptSequenceStep item) => item.content;

  @override
  FixedPromptSequenceStep copyItemWithText(
    FixedPromptSequenceStep item, {
    required String title,
    required String content,
  }) => item.copyWith(title: title, content: content);

  String _snapshot() {
    syncSelectedItem();
    return jsonEncode([
      nameController.text,
      for (final step in items) [step.id, step.title, step.content],
    ]);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue?.steps ?? const [];
    initEditorItems(
      initial.isNotEmpty
          ? initial
          : [
              FixedPromptSequenceStep(
                id: generateEntityId(),
                title: buildFixedPromptStepFallbackTitle(1),
                content: '',
              ),
            ],
    );
    captureInitialSnapshot(_snapshot());
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildEditorPage(
    title: widget.initialValue == null ? '新增固定顺序提示词' : '编辑固定顺序提示词',
    targetName: '固定顺序提示词',
    helpText: '选择步骤后编辑标题和内容，用上移／下移调整顺序。每一步作为用户消息使用；聊天页可填入输入框或发送当前步骤，不会自动整组连发。',
    snapshotBuilder: _snapshot,
    onSubmit: _handleSubmit,
    builder: (context, constraints, shouldScroll) => buildMasterDetailSection(
      constraints: constraints,
      shouldScroll: shouldScroll,
      itemLabel: '步骤',
      addLabel: '新增步骤',
      selectLabel: '选择步骤',
      deleteLabel: '删除当前步骤',
      emptyText: '请先选择左侧步骤。',
      header: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppTextField.form(
          controller: nameController,
          readOnly: isSaving,
          decoration: const InputDecoration(
            labelText: '序列名称',
            hintText: '例如：代码审阅对比流程',
          ),
        ),
      ),
      onAdd: () => setState(
        () => insertItem(
          FixedPromptSequenceStep(
            id: generateEntityId(),
            title: buildFixedPromptStepFallbackTitle(items.length + 1),
            content: '',
          ),
        ),
      ),
      onDeleteSelected: items.length > 1
          ? () => setState(() => removeSelected(minCount: 1))
          : null,
      detailBuilder: (_, _, {required isWide, required expandContent}) =>
          Column(
            mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField.form(
                controller: itemTitleController,
                readOnly: isSaving,
                decoration: const InputDecoration(
                  labelText: '步骤标题',
                  hintText: '例如：先总结需求、再列方案',
                ),
              ),
              const SizedBox(height: 8),
              SettingsExpandedTextField(
                fieldKey: const ValueKey('fixed-step-content-field'),
                controller: itemContentController,
                expand: expandContent,
                readOnly: isSaving,
                decoration: const InputDecoration(
                  labelText: '步骤内容',
                  hintText: '输入这一轮要发送给模型的用户提示词。',
                ),
              ),
            ],
          ),
    ),
  );

  Future<void> _handleSubmit() async {
    syncSelectedItem();
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showFormSnackBar('请填写序列名称');
      return;
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i].title.isEmpty || items[i].content.isEmpty) {
        setState(() => selectItem(i));
        showFormSnackBar(items[i].title.isEmpty ? '请填写每个步骤的标题' : '请填写每个步骤的内容');
        return;
      }
    }
    await submitPageAndClose(
      () => widget.onSubmit(
        FixedPromptSequenceFormData(
          name: name,
          steps: List.unmodifiable(items),
        ),
      ),
    );
  }
}
