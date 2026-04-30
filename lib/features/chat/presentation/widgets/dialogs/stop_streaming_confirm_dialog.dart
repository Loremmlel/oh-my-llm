import 'package:flutter/material.dart';

/// 终止模型回复前的确认弹窗，避免误触。
class StopStreamingConfirmDialog extends StatelessWidget {
  const StopStreamingConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('终止本次回答？'),
      content: const Text('会保留当前已经生成的内容，并立即停止后续回复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续生成'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('终止回答'),
        ),
      ],
    );
  }
}
