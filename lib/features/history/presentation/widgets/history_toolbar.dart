import 'package:flutter/material.dart';

/// 历史页工具栏，负责搜索、全选和批量删除。
class HistoryToolbar extends StatelessWidget {
  const HistoryToolbar({
    super.key,
    required this.searchController,
    required this.selectedCount,
    required this.hasConversations,
    required this.onSearchChanged,
    required this.onSelectAllPressed,
    required this.onDeletePressed,
  });

  final TextEditingController searchController;
  final int selectedCount;
  final bool hasConversations;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onSelectAllPressed;
  final VoidCallback? onDeletePressed;

  @override
  /// 构建搜索框和批量操作按钮。
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              labelText: '搜索历史对话',
              hintText: '仅匹配标题和用户消息',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: hasConversations ? onSelectAllPressed : null,
          icon: const Icon(Icons.select_all_rounded),
          label: const Text('全选当前结果'),
        ),
        FilledButton.icon(
          onPressed: onDeletePressed,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(selectedCount == 0 ? '批量删除' : '删除 $selectedCount 项'),
        ),
      ],
    );
  }
}
