import 'package:flutter/material.dart';

import 'app_dialog_actions.dart';

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
    this.isDestructive = false,
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

  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return AppDialogActions(
      onCancel: () => Navigator.of(context).maybePop(false),
      child: AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
