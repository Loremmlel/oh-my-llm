import 'package:flutter/material.dart';

import '../../../../core/utils/id_generator.dart';
import '../../domain/models/prompt_template.dart';

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
class _PromptTemplateFormDialogState extends State<PromptTemplateFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _systemPromptController;
  late List<_EditablePromptMessage> _messages;
  bool _isSaving = false;

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

    return AlertDialog(
      title: Text(isEditing ? '编辑 Prompt 模板' : '新增 Prompt 模板'),
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
                    labelText: '模板名称',
                    hintText: '例如：代码审阅助手',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _systemPromptController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'System 指令',
                    hintText: '你是我的人工智能助手，协助我完成各种任务。',
                  ),
                  validator: _validateRequired,
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '附加消息',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                          onPressed: () =>
                              _addMessage(PromptMessageRole.assistant),
                          icon: const Icon(Icons.smart_toy_outlined),
                          label: const Text('新增 Assistant'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_messages.isEmpty)
                  const Text('可以只保存 system 指令，也可以继续追加 user/assistant 消息。'),
                for (var index = 0; index < _messages.length; index++) ...[
                  _PromptMessageEditor(
                    key: ValueKey(_messages[index].id),
                    index: index,
                    message: _messages[index],
                    canMoveUp: index > 0,
                    canMoveDown: index < _messages.length - 1,
                    onRoleChanged: (role) {
                      setState(() {
                        _messages[index] = _messages[index].copyWith(
                          role: role,
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

  /// 向模板中追加一条附加消息。
  void _addMessage(PromptMessageRole role) {
    setState(() {
      _messages.add(
        _EditablePromptMessage(
          id: generateEntityId(),
          role: role,
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final messages = _messages
        .map((message) {
          return PromptMessage(
            id: message.id,
            role: message.role,
            content: message.controller.text.trim(),
          );
        })
        .where((message) => message.content.isNotEmpty)
        .toList(growable: false);

    setState(() {
      _isSaving = true;
    });

    await widget.onSubmit(
      PromptTemplateFormData(
        name: _nameController.text.trim(),
        systemPrompt: _systemPromptController.text.trim(),
        messages: messages,
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

/// 单条 Prompt 附加消息的编辑面板。
class _PromptMessageEditor extends StatelessWidget {
  const _PromptMessageEditor({
    required this.index,
    required this.message,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRoleChanged,
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
    required this.controller,
  });

  final String id;
  final PromptMessageRole role;
  final TextEditingController controller;

  _EditablePromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    TextEditingController? controller,
  }) {
    return _EditablePromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      controller: controller ?? this.controller,
    );
  }
}
