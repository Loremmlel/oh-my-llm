import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/app_selection_toolbar.dart';

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
    this.onNewConversation,
    this.onEnterSelection,
  });

  final HistoryToolbarMode mode;
  final TextEditingController? searchController;
  final VoidCallback? onNewConversation;
  final VoidCallback? onEnterSelection;

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
      return AppSelectionToolbar(
        selectedCount: selectedCount,
        onSelectCurrentPage: hasConversations ? onSelectCurrentPage : null,
        onClearSelection: onClearSelection,
        onDelete: onDeletePressed,
        deleteLabel: selectedCount == 0 ? '批量删除' : '删除 $selectedCount 项',
        onExitSelection: onExitSelection,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏占满可用父宽；宽屏限宽避免无限拉伸。
        final searchWidth = math.min(360.0, constraints.maxWidth);
        final search = SizedBox(
          width: searchWidth,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            // 只保留 hint + 前缀图标的紧凑单行：label 会把整行撑高，
            // 让工具栏在整页宽度上显得空且重。
            decoration: InputDecoration(
              hintText: '搜索历史对话',
              isDense: true,
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
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (onNewConversation != null)
              FilledButton.icon(
                onPressed: onNewConversation,
                icon: const Icon(Icons.add),
                label: const Text('新对话'),
              ),
            if (onEnterSelection != null)
              OutlinedButton.icon(
                onPressed: hasConversations ? onEnterSelection : null,
                icon: const Icon(Icons.checklist),
                label: const Text('批量选择'),
              ),
          ],
        );
        if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            AppBreakpoints.contentMasterDetail) {
          return Row(children: [actions, const Spacer(), search]);
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [actions, search],
        );
      },
    );
  }
}
