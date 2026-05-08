import 'package:flutter/material.dart';

import '../../../../core/utils/id_generator.dart';
import '../../../../core/widgets/adaptive_master_detail_layout.dart';
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

/// 固定顺序提示词表单的输入与选中步骤状态。
class _FixedPromptSequenceFormDialogState
    extends State<FixedPromptSequenceFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final List<_EditableFixedPromptSequenceStep> _steps;
  late String _selectedStepId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _steps = (widget.initialValue?.steps ?? const <FixedPromptSequenceStep>[])
        .map((step) {
          return _EditableFixedPromptSequenceStep(
            id: step.id,
            titleController: TextEditingController(text: step.title),
            contentController: TextEditingController(text: step.content),
          );
        })
        .toList(growable: true);
    if (_steps.isEmpty) {
      _steps.add(
        _EditableFixedPromptSequenceStep(
          id: generateEntityId(),
          titleController: TextEditingController(
            text: buildFixedPromptStepFallbackTitle(1),
          ),
          contentController: TextEditingController(),
        ),
      );
    }
    _selectedStepId = _steps.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final step in _steps) {
      step.titleController.dispose();
      step.contentController.dispose();
    }
    super.dispose();
  }

  @override
  /// 构建固定顺序提示词的主从式编辑器。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑固定顺序提示词' : '新增固定顺序提示词',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 1080,
      child: AdaptiveMasterDetailLayout(
        key: const ValueKey('fixed-prompt-sequence-form-layout'),
        breakpoint: 900,
        masterWidth: 340,
        minHeight: 620,
        compactChild: _buildCompactLayout(context),
        master: _buildWideMasterPane(context),
        detail: _buildWidePane(
          context: context,
          key: const ValueKey('fixed-prompt-sequence-detail-pane'),
          child: _buildDetailContent(context),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMasterContent(context),
        const SizedBox(height: 16),
        _buildCompactPane(
          context: context,
          key: const ValueKey('fixed-prompt-sequence-detail-pane'),
          child: _buildDetailContent(context),
        ),
      ],
    );
  }

  Widget _buildWidePane({
    required BuildContext context,
    required Widget child,
    required Key key,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _buildWideMasterPane(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('fixed-prompt-sequence-master-pane'),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMasterHeader(context),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  return _FixedPromptStepListTile(
                    step: _steps[index],
                    index: index,
                    isSelected: _steps[index].id == _selectedStepId,
                    onTap: () {
                      setState(() {
                        _selectedStepId = _steps[index].id;
                      });
                    },
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPane({
    required BuildContext context,
    required Widget child,
    required Key key,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildMasterContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMasterHeader(context),
        const SizedBox(height: 16),
        for (var index = 0; index < _steps.length; index++) ...[
          _FixedPromptStepListTile(
            step: _steps[index],
            index: index,
            isSelected: _steps[index].id == _selectedStepId,
            onTap: () {
              setState(() {
                _selectedStepId = _steps[index].id;
              });
            },
          ),
          if (index != _steps.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMasterHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('步骤列表', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildNameField(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新增步骤'),
            ),
            OutlinedButton.icon(
              onPressed: _canMoveSelectedUp() ? () => _moveSelected(-1) : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              label: const Text('上移'),
            ),
            OutlinedButton.icon(
              onPressed: _canMoveSelectedDown() ? () => _moveSelected(1) : null,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const Text('下移'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '左侧用于切换步骤与调整顺序，右侧编辑当前步骤的标题和内容。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDetailContent(BuildContext context) {
    final selected = _selectedStep;
    if (selected == null) {
      return const Text('请先选择左侧步骤。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('步骤详情', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '这里的每一步都会作为用户消息逐步使用，聊天页不会自动整组发送。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('fixed-step-title-${selected.id}'),
          controller: selected.titleController,
          decoration: const InputDecoration(
            labelText: '步骤标题',
            hintText: '例如：先总结需求、再列方案',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('fixed-step-content-${selected.id}'),
          controller: selected.contentController,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: '步骤内容',
            hintText: '输入这一轮要发送给模型的用户提示词。',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _steps.length > 1 ? _removeSelectedStep : null,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除当前步骤'),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '序列名称',
        hintText: '例如：代码审阅对比流程',
      ),
    );
  }

  _EditableFixedPromptSequenceStep? get _selectedStep {
    for (final step in _steps) {
      if (step.id == _selectedStepId) {
        return step;
      }
    }
    return null;
  }

  int get _selectedStepIndex {
    return _steps.indexWhere((step) => step.id == _selectedStepId);
  }

  void _addStep() {
    final newStep = _EditableFixedPromptSequenceStep(
      id: generateEntityId(),
      titleController: TextEditingController(
        text: buildFixedPromptStepFallbackTitle(_steps.length + 1),
      ),
      contentController: TextEditingController(),
    );

    setState(() {
      _steps.add(newStep);
      _selectedStepId = newStep.id;
    });
  }

  void _removeSelectedStep() {
    final index = _selectedStepIndex;
    if (index < 0 || _steps.length <= 1) {
      return;
    }

    setState(() {
      final removed = _steps.removeAt(index);
      removed.titleController.dispose();
      removed.contentController.dispose();
      _selectedStepId = _steps[index > 0 ? index - 1 : 0].id;
    });
  }

  bool _canMoveSelectedUp() => _selectedStepIndex > 0;

  bool _canMoveSelectedDown() =>
      _selectedStepIndex >= 0 && _selectedStepIndex < _steps.length - 1;

  void _moveSelected(int delta) {
    final index = _selectedStepIndex;
    final nextIndex = index + delta;
    if (index < 0 || nextIndex < 0 || nextIndex >= _steps.length) {
      return;
    }

    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(nextIndex, step);
      _selectedStepId = step.id;
    });
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showFormSnackBar('请填写序列名称');
      return;
    }

    for (final step in _steps) {
      if (step.titleController.text.trim().isEmpty) {
        _selectedStepId = step.id;
        setState(() {});
        showFormSnackBar('请填写每个步骤的标题');
        return;
      }
      if (step.contentController.text.trim().isEmpty) {
        _selectedStepId = step.id;
        setState(() {});
        showFormSnackBar('请填写每个步骤的内容');
        return;
      }
    }

    final steps = _steps
        .map((step) {
          return FixedPromptSequenceStep(
            id: step.id,
            title: step.titleController.text.trim(),
            content: step.contentController.text.trim(),
          );
        })
        .toList(growable: false);

    await submitAndClose(() {
      return widget.onSubmit(
        FixedPromptSequenceFormData(name: name, steps: steps),
      );
    });
  }
}

/// 左侧步骤标题项。
class _FixedPromptStepListTile extends StatelessWidget {
  const _FixedPromptStepListTile({
    required this.step,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final _EditableFixedPromptSequenceStep step;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '步骤 ${index + 1} · ${step.titleController.text.trim()}',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                step.preview,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表单内使用的可编辑步骤包装。
class _EditableFixedPromptSequenceStep {
  const _EditableFixedPromptSequenceStep({
    required this.id,
    required this.titleController,
    required this.contentController,
  });

  final String id;
  final TextEditingController titleController;
  final TextEditingController contentController;

  String get preview {
    final text = contentController.text.trim().replaceAll('\n', ' ');
    if (text.isEmpty) {
      return '点击右侧填写步骤内容';
    }
    if (text.length <= 36) {
      return text;
    }
    return '${text.substring(0, 36)}...';
  }
}
