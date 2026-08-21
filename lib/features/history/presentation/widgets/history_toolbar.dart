import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 历史页工具栏的双模式。
enum HistoryToolbarMode { search, selection }

/// 历史页工具栏。
///
/// normal 模式提供搜索框（带清空按钮）；selection 模式显示已选数量、
/// 选择当前页、清除、批量删除与退出。
class HistoryToolbar extends StatelessWidget {
  const HistoryToolbar({
    super.key,
    required this.mode,
    required this.selectedCount,
    required this.hasConversations,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSelectCurrentPage,
    required this.onClearSelection,
    required this.onDeletePressed,
    required this.onExitSelection,
    this.searchController,
  });

  final HistoryToolbarMode mode;
  final TextEditingController? searchController;

  /// 当前页已选条数（selection 模式）。
  final int selectedCount;

  /// 数据库中是否存在任何会话（决定选择当前页是否可用）。
  final bool hasConversations;

  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final VoidCallback onSelectCurrentPage;
  final VoidCallback onClearSelection;
  final VoidCallback? onDeletePressed;
  final VoidCallback onExitSelection;

  @override
  Widget build(BuildContext context) {
    if (mode == HistoryToolbarMode.selection) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('已选择 $selectedCount 项'),
          OutlinedButton(
            onPressed: hasConversations ? onSelectCurrentPage : null,
            child: const Text('选择当前页'),
          ),
          OutlinedButton(onPressed: onClearSelection, child: const Text('清除')),
          FilledButton.icon(
            onPressed: onDeletePressed,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(selectedCount == 0 ? '批量删除' : '删除 $selectedCount 项'),
          ),
          IconButton(
            tooltip: '退出选择',
            onPressed: onExitSelection,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏占满可用父宽；宽屏限宽避免无限拉伸。
        final searchWidth = math.min(360.0, constraints.maxWidth);
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  labelText: '搜索历史对话',
                  hintText: '仅匹配标题和用户消息',
                  prefixIcon: const Icon(Icons.search_rounded),
                  // TextEditingController 是 Listenable；跟随输入显隐清空按钮。
                  suffixIcon: searchController == null
                      ? null
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: searchController!,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    searchController?.clear();
                                    onSearchCleared();
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
