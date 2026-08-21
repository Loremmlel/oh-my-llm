import 'package:flutter/material.dart';

/// 历史页空状态提示。
///
/// 搜索无结果时提供清除关键词的恢复入口。
class EmptyHistoryView extends StatelessWidget {
  const EmptyHistoryView({
    super.key,
    required this.hasConversations,
    required this.searchKeyword,
    this.onClearSearch,
  });

  final bool hasConversations;
  final String searchKeyword;

  /// 清除当前搜索关键词；为空时不展示入口。
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final isSearchMiss = hasConversations && searchKeyword.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isSearchMiss
                ? '没有匹配“${searchKeyword.trim()}”的历史会话。'
                : '还没有可展示的历史会话。',
            textAlign: TextAlign.center,
          ),
          if (isSearchMiss && onClearSearch != null)
            TextButton(onPressed: onClearSearch, child: const Text('清除搜索')),
        ],
      ),
    );
  }
}
