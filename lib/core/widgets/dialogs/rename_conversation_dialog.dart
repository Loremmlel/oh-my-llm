import 'package:flutter/material.dart';

/// 重命名会话标题的对话框。
///
/// 供聊天页和历史页共用，避免代码重复。
class RenameConversationDialog extends StatefulWidget {
  const RenameConversationDialog({
    required this.initialTitle,
    this.title = '重命名会话',
    this.labelText = '会话标题',
    super.key,
  });

  /// 当前标题，作为输入框初始值。
  final String initialTitle;

  /// 弹窗标题文案。
  final String title;

  /// 输入框标签文案。
  final String labelText;

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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _titleController,
        decoration: InputDecoration(labelText: widget.labelText),
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
