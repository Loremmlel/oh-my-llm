import 'package:flutter/material.dart';

import '../../../../core/widgets/notification_bubble_context_ext.dart';

/// 设置页通用的通知气泡辅助函数。
///
/// 内部调用新的右上角气泡通知系统，替换了旧的 SnackBar。
void showSettingsSnackbar(BuildContext context, String message) {
  if (!context.mounted) return;
  context.showBubble(message);
}

/// 设置实体卡片通用的编辑/删除操作按钮组。
List<Widget> editDeleteActions({
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) => [
  OutlinedButton.icon(
    onPressed: onEdit,
    icon: const Icon(Icons.edit_outlined),
    label: const Text('编辑'),
  ),
  OutlinedButton.icon(
    onPressed: onDelete,
    icon: const Icon(Icons.delete_outline_rounded),
    label: const Text('删除'),
  ),
];
