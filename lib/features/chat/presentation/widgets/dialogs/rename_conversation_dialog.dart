import 'package:flutter/material.dart';

/// 用于重命名会话标题的对话框。
class RenameConversationDialog extends StatefulWidget {
  const RenameConversationDialog({required this.initialTitle, super.key});

  final String initialTitle;

  @override
  State<RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

/// 重命名对话框的输入与提交状态。
class _RenameConversationDialogState extends State<RenameConversationDialog> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  /// 构建标题输入框与确认/取消操作。
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改对话标题'),
      content: TextField(
        controller: _titleController,
        decoration: const InputDecoration(labelText: '对话标题'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final nextTitle = _titleController.text.trim();
            if (nextTitle.isEmpty) {
              return;
            }

            Navigator.of(context).pop(nextTitle);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
