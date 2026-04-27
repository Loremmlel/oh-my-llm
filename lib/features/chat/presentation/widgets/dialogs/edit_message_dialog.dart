import 'package:flutter/material.dart';

class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({required this.initialContent, super.key});

  final String initialContent;

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑用户消息'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _contentController,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: '消息内容',
            alignLabelWithHint: true,
          ),
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final nextContent = _contentController.text.trim();
            if (nextContent.isEmpty) {
              return;
            }

            Navigator.of(context).pop(nextContent);
          },
          child: const Text('保存并重算'),
        ),
      ],
    );
  }
}
