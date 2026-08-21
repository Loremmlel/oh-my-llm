import 'package:flutter/material.dart';

/// 收藏列表选择模式的固定工具栏。
///
/// 展示已选数量，提供选择当前页、清除、移动、删除与退出选择；移动和
/// 删除仅在存在选中项时可用。
class FavoriteSelectionToolbar extends StatelessWidget {
  const FavoriteSelectionToolbar({
    required this.selectedCount,
    required this.currentPageIds,
    required this.onSelectCurrentPage,
    required this.onClearSelection,
    required this.onMove,
    required this.onDelete,
    required this.onExitSelection,
    super.key,
  });

  /// 已选中数量。
  final int selectedCount;

  /// 当前页全部条目 ID（"选择当前页"的数据源）。
  final Set<String> currentPageIds;

  final VoidCallback onSelectCurrentPage;
  final VoidCallback onClearSelection;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onExitSelection;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Row(
      children: [
        Text(
          hasSelection ? '已选择 $selectedCount 项' : '未选择任何收藏',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const Spacer(),
        TextButton(
          onPressed: currentPageIds.isEmpty ? null : onSelectCurrentPage,
          child: const Text('选择当前页'),
        ),
        TextButton(
          onPressed: hasSelection ? onClearSelection : null,
          child: const Text('清除'),
        ),
        FilledButton.tonal(
          onPressed: hasSelection ? onMove : null,
          child: const Text('移动'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: hasSelection ? onDelete : null,
          child: const Text('删除'),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onExitSelection, child: const Text('退出选择')),
      ],
    );
  }
}
