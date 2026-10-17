import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

Future<bool> confirmSettingsDeletion(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          AppConfirmDialog(title: title, message: message, confirmLabel: title),
    ) ==
    true;

/// 设置页通用的通知气泡辅助函数。
///
/// 内部调用新的右上角气泡通知系统，替换了旧的 SnackBar。
void showSettingsSnackbar(BuildContext context, String message) {
  if (!context.mounted) return;
  context.showBubble(message);
}

/// 提示词记录的紧凑操作，保持键盘和触摸入口。
List<Widget> editDeleteActions({
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) => [
  IconButton(
    onPressed: onEdit,
    icon: const Icon(Icons.edit_outlined),
    tooltip: '编辑',
  ),
  PopupMenuButton<String>(
    tooltip: '更多操作',
    icon: const Icon(Icons.more_horiz, size: 18),
    onSelected: (_) => onDelete(),
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'delete',
        child: Text(
          '删除',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ],
  ),
];
