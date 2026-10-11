import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 分页浏览的选择操作；选择集合与删除确认仍由所属页面管理。
class AppSelectionToolbar extends StatelessWidget {
  const AppSelectionToolbar({
    required this.selectedCount,
    required this.onSelectCurrentPage,
    required this.onClearSelection,
    required this.onDelete,
    required this.onExitSelection,
    this.onMove,
    this.deleteLabel = '删除',
    super.key,
  });

  final int selectedCount;
  final VoidCallback? onSelectCurrentPage;
  final VoidCallback? onClearSelection;
  final VoidCallback? onDelete;
  final VoidCallback onExitSelection;
  final VoidCallback? onMove;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('已选择 $selectedCount 项', style: theme.textTheme.labelLarge),
          TextButton(
            onPressed: onSelectCurrentPage,
            child: const Text('选择当前页'),
          ),
          TextButton(onPressed: onClearSelection, child: const Text('清除')),
          if (onMove != null)
            TextButton.icon(
              onPressed: selectedCount > 0 ? onMove : null,
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('移动'),
            ),
          TextButton.icon(
            onPressed: onDelete,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(deleteLabel),
          ),
          TextButton(onPressed: onExitSelection, child: const Text('退出选择')),
        ],
      ),
    );
  }
}
