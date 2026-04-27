import 'package:flutter/material.dart';

import '../../../../core/utils/id_generator.dart';
import '../../domain/models/fixed_prompt_sequence.dart';

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
    extends State<FixedPromptSequenceFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late List<_EditableFixedPromptSequenceStep> _steps;
  bool _isSaving = false;

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

    return AlertDialog(
      title: Text(isEditing ? '编辑固定顺序提示词' : '新增固定顺序提示词'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '序列名称',
                    hintText: '例如：代码审阅对比流程',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      '顺序步骤',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                const SizedBox(height: 12),
                if (_steps.isEmpty) const Text('先添加至少一个步骤，聊天页才能按顺序填入或发送。'),
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
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSubmit,
          child: Text(_isSaving ? '保存中...' : '保存'),
        ),
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
    if (!_formKey.currentState!.validate()) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少要保留一个非空步骤')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await widget.onSubmit(
      FixedPromptSequenceFormData(
        name: _nameController.text.trim(),
        steps: steps,
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 校验必填字段是否为空。
  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }

    return null;
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
