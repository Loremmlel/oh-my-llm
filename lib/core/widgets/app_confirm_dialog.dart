import 'package:flutter/material.dart';

/// 通用确认弹窗。
///
/// 适用于标题 + 消息 + 取消/确认 模式的简单确认场景。
/// 取消总是返回 `false`，确认总是返回 `true`。
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.title,
    required this.message,
    this.cancelLabel = '取消',
    required this.confirmLabel,
    super.key,
  });

  /// 弹窗标题。
  final String title;

  /// 弹窗正文。
  final String message;

  /// 取消按钮文案。
  final String cancelLabel;

  /// 确认按钮文案。
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
