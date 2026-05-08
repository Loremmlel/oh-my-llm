import 'package:flutter/material.dart';

import '../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../../../core/utils/id_generator.dart';
import '../../domain/models/fixed_prompt_sequence.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

/// 固定顺序提示词表单提交数据。
class FixedPromptSequenceFormData {
  const FixedPromptSequenceFormData({required this.name, required this.steps});

  final String name;
  final List<FixedPromptSequenceStep> steps;
}

/// 新增或编辑固定顺序提示词序列的对话框。
class FixedPromptSequenceFormDialog extends StatefulWidget {
  const FixedPromptSequenceFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(FixedPromptSequenceFormData formData) onSubmit;
  final FixedPromptSequence? initialValue;

  @override
  State<FixedPromptSequenceFormDialog> createState() =>
      _FixedPromptSequenceFormDialogState();
}

/// 固定顺序提示词表单的输入与步骤顺序状态。
class _FixedPromptSequenceFormDialogState
    extends State<FixedPromptSequenceFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late List<_EditableFixedPromptSequenceStep> _steps;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _steps = (widget.initialValue?.steps ?? const [])
        .map((step) {
          return _EditableFixedPromptSequenceStep(
            id: step.id,
            controller: TextEditingController(text: step.content),
          );
        })
        .toList(growable: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final step in _steps) {
      step.controller.dispose();
    }
    super.dispose();
  }

  @override
  /// 构建固定顺序提示词序列编辑表单和步骤列表。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑固定顺序提示词' : '新增固定顺序提示词',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 980,
      child: AdaptiveMasterDetailLayout(
        key: const ValueKey('fixed-prompt-sequence-form-layout'),
        breakpoint: 840,
        masterWidth: 320,
        minHeight: 560,
        compactChild: _buildCompactForm(context),
        master: _buildMetaPane(context),
        detail: _buildStepsPane(context),
      ),
    );
  }

  Widget _buildCompactForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameField(),
        const SizedBox(height: 20),
        _buildStepsHeader(context),
        const SizedBox(height: 12),
        _buildStepsList(),
      ],
    );
  }

  Widget _buildMetaPane(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('序列基础信息', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildNameField(),
            const SizedBox(height: 16),
            Text(
              '左侧只维护序列名称和使用说明；右侧专门编辑步骤内容、顺序和删除操作。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              '这里的每一步都会作为用户消息逐步使用，聊天页不会自动整组发送。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsPane(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepsHeader(context),
            const SizedBox(height: 12),
            _buildStepsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '序列名称',
        hintText: '例如：代码审阅对比流程',
      ),
      validator: validateRequired,
    );
  }

  Widget _buildStepsHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('顺序步骤', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新增步骤'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '这里的每一步都会作为用户消息逐步使用，聊天页不会自动整组发送。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildStepsList() {
    if (_steps.isEmpty) {
      return const Text('先添加至少一个步骤，聊天页才能按顺序填入或发送。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _steps.length; index++) ...[
          _FixedPromptSequenceStepEditor(
            key: ValueKey(_steps[index].id),
            index: index,
            step: _steps[index],
            canMoveUp: index > 0,
            canMoveDown: index < _steps.length - 1,
            onMoveUp: () => _moveStep(index, index - 1),
            onMoveDown: () => _moveStep(index, index + 1),
            onDelete: () => _removeStep(index),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// 追加一个新的顺序步骤。
  void _addStep() {
    setState(() {
      _steps.add(
        _EditableFixedPromptSequenceStep(
          id: generateEntityId(),
          controller: TextEditingController(),
        ),
      );
    });
  }

  /// 调整步骤顺序。
  void _moveStep(int from, int to) {
    setState(() {
      final step = _steps.removeAt(from);
      _steps.insert(to, step);
    });
  }

  /// 删除指定步骤并释放控制器。
  void _removeStep(int index) {
    setState(() {
      final step = _steps.removeAt(index);
      step.controller.dispose();
    });
  }

  /// 提交序列并过滤掉空白步骤。
  Future<void> _handleSubmit() async {
    if (!validateForm()) {
      return;
    }

    final steps = _steps
        .map((step) {
          return FixedPromptSequenceStep(
            id: step.id,
            content: step.controller.text.trim(),
          );
        })
        .where((step) => step.content.isNotEmpty)
        .toList(growable: false);

    if (steps.isEmpty) {
      showFormSnackBar('至少要保留一个非空步骤');
      return;
    }

    await submitAndClose(() {
      return widget.onSubmit(
        FixedPromptSequenceFormData(
          name: _nameController.text.trim(),
          steps: steps,
        ),
      );
    });
  }
}

/// 单个顺序步骤的编辑面板。
class _FixedPromptSequenceStepEditor extends StatelessWidget {
  const _FixedPromptSequenceStepEditor({
    required this.index,
    required this.step,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    super.key,
  });

  final int index;
  final _EditableFixedPromptSequenceStep step;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  /// 构建步骤顺序和内容编辑区。
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text('步骤 ${index + 1}'),
                const Spacer(),
                IconButton(
                  onPressed: canMoveUp ? onMoveUp : null,
                  tooltip: '上移',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  onPressed: canMoveDown ? onMoveDown : null,
                  tooltip: '下移',
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除步骤',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: step.controller,
              minLines: 2,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '步骤内容',
                hintText: '输入这一轮要发送给模型的用户提示词。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单内使用的可编辑步骤包装，持有独立控制器。
class _EditableFixedPromptSequenceStep {
  const _EditableFixedPromptSequenceStep({
    required this.id,
    required this.controller,
  });

  final String id;
  final TextEditingController controller;
}
