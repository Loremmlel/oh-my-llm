import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_selection_toolbar.dart';

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
    return AppSelectionToolbar(
      selectedCount: selectedCount,
      onSelectCurrentPage: currentPageIds.isEmpty ? null : onSelectCurrentPage,
      onClearSelection: hasSelection ? onClearSelection : null,
      onMove: onMove,
      onDelete: hasSelection ? onDelete : null,
      onExitSelection: onExitSelection,
    );
  }
}
