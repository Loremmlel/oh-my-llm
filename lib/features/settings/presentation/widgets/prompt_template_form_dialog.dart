import 'package:flutter/material.dart';

import '../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../../../core/utils/id_generator.dart';
import '../../domain/models/prompt_template.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

/// Prompt 模板表单提交数据。
class PromptTemplateFormData {
  const PromptTemplateFormData({
    required this.name,
    required this.systemPrompt,
    required this.messages,
  });

  final String name;
  final String systemPrompt;
  final List<PromptMessage> messages;
}

/// 新增或编辑 Prompt 模板的对话框。
class PromptTemplateFormDialog extends StatefulWidget {
  const PromptTemplateFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(PromptTemplateFormData formData) onSubmit;
  final PromptTemplate? initialValue;

  @override
  State<PromptTemplateFormDialog> createState() =>
      _PromptTemplateFormDialogState();
}

/// Prompt 模板表单的输入与排序状态。
class _PromptTemplateFormDialogState extends State<PromptTemplateFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _systemPromptController;
  late List<_EditablePromptMessage> _messages;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _systemPromptController = TextEditingController(
      text: widget.initialValue?.systemPrompt ?? '',
    );
    _messages = (widget.initialValue?.messages ?? const [])
        .map((message) {
          return _EditablePromptMessage(
            id: message.id,
            role: message.role,
            placement: message.placement,
            controller: TextEditingController(text: message.content),
          );
        })
        .toList(growable: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _systemPromptController.dispose();
    for (final message in _messages) {
      message.controller.dispose();
    }
    super.dispose();
  }

  @override
  /// 构建 Prompt 模板编辑表单和消息列表。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑 Prompt 模板' : '新增 Prompt 模板',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 980,
      child: AdaptiveMasterDetailLayout(
        key: const ValueKey('prompt-template-form-layout'),
        breakpoint: 840,
        masterWidth: 320,
        minHeight: 560,
        compactChild: _buildCompactForm(context),
        master: _buildMetaPane(context),
        detail: _buildMessagesPane(context),
      ),
    );
  }

  Widget _buildCompactForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameField(),
        const SizedBox(height: 12),
        _buildSystemPromptField(),
        const SizedBox(height: 20),
        _buildMessageHeader(context),
        const SizedBox(height: 12),
        _buildMessageList(),
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
            Text('模板基础信息', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildNameField(),
            const SizedBox(height: 12),
            _buildSystemPromptField(),
            const SizedBox(height: 16),
            Text(
              '左侧维护模板名称和 System 指令；右侧单独管理附加消息的顺序、角色和拼接位置。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesPane(BuildContext context) {
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
            _buildMessageHeader(context),
            const SizedBox(height: 12),
            _buildMessageList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '模板名称',
        hintText: '例如：代码审阅助手',
      ),
      validator: validateRequired,
    );
  }

  Widget _buildSystemPromptField() {
    return TextFormField(
      controller: _systemPromptController,
      minLines: 8,
      maxLines: 14,
      decoration: const InputDecoration(
        labelText: 'System 指令',
        hintText: '你是我的人工智能助手，协助我完成各种任务。',
      ),
      validator: validateRequired,
    );
  }

  Widget _buildMessageHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('附加消息', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addMessage(PromptMessageRole.user),
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('新增 User'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addMessage(PromptMessageRole.assistant),
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('新增 Assistant'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Text('可以只保存 system 指令，也可以继续追加 user/assistant 消息。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _messages.length; index++) ...[
          _PromptMessageEditor(
            key: ValueKey(_messages[index].id),
            index: index,
            message: _messages[index],
            canMoveUp: index > 0,
            canMoveDown: index < _messages.length - 1,
            onRoleChanged: (role) {
              setState(() {
                _messages[index] = _messages[index].copyWith(role: role);
              });
            },
            onPlacementChanged: (placement) {
              setState(() {
                _messages[index] = _messages[index].copyWith(
                  placement: placement,
                );
              });
            },
            onMoveUp: () => _moveMessage(index, index - 1),
            onMoveDown: () => _moveMessage(index, index + 1),
            onDelete: () => _removeMessage(index),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// 向模板中追加一条附加消息。
  void _addMessage(PromptMessageRole role) {
    setState(() {
      _messages.add(
        _EditablePromptMessage(
          id: generateEntityId(),
          role: role,
          placement: PromptMessagePlacement.before,
          controller: TextEditingController(),
        ),
      );
    });
  }

  /// 调整附加消息的顺序。
  void _moveMessage(int from, int to) {
    setState(() {
      final message = _messages.removeAt(from);
      _messages.insert(to, message);
    });
  }

  /// 删除指定附加消息并释放对应控制器。
  void _removeMessage(int index) {
    setState(() {
      final message = _messages.removeAt(index);
      message.controller.dispose();
    });
  }

  /// 提交模板并过滤掉空消息。
  Future<void> _handleSubmit() async {
    if (!validateForm()) {
      return;
    }

    final messages = _messages
        .map((message) {
          return PromptMessage(
            id: message.id,
            role: message.role,
            content: message.controller.text.trim(),
            placement: message.placement,
          );
        })
        .where((message) => message.content.isNotEmpty)
        .toList(growable: false);

    await submitAndClose(() {
      return widget.onSubmit(
        PromptTemplateFormData(
          name: _nameController.text.trim(),
          systemPrompt: _systemPromptController.text.trim(),
          messages: messages,
        ),
      );
    });
  }
}

/// 单条 Prompt 附加消息的编辑面板。
class _PromptMessageEditor extends StatelessWidget {
  const _PromptMessageEditor({
    required this.index,
    required this.message,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRoleChanged,
    required this.onPlacementChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    super.key,
  });

  final int index;
  final _EditablePromptMessage message;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<PromptMessageRole> onRoleChanged;
  final ValueChanged<PromptMessagePlacement> onPlacementChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  /// 构建消息角色、顺序和内容编辑区。
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
                Text('消息 ${index + 1}'),
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
                  tooltip: '删除消息',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PromptMessageRole>(
              initialValue: message.role,
              items: PromptMessageRole.values
                  .map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.label),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  onRoleChanged(value);
                }
              },
              decoration: const InputDecoration(labelText: '角色'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PromptMessagePlacement>(
              initialValue: message.placement,
              items: PromptMessagePlacement.values
                  .map((placement) {
                    return DropdownMenuItem(
                      value: placement,
                      child: Text(placement.label),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  onPlacementChanged(value);
                }
              },
              decoration: const InputDecoration(labelText: '拼接位置'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: message.controller,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '消息内容'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单内使用的可编辑消息包装，持有独立控制器。
class _EditablePromptMessage {
  const _EditablePromptMessage({
    required this.id,
    required this.role,
    required this.placement,
    required this.controller,
  });

  final String id;
  final PromptMessageRole role;
  final PromptMessagePlacement placement;
  final TextEditingController controller;

  _EditablePromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    PromptMessagePlacement? placement,
    TextEditingController? controller,
  }) {
    return _EditablePromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      placement: placement ?? this.placement,
      controller: controller ?? this.controller,
    );
  }
}
