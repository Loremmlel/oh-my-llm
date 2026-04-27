import 'package:flutter/material.dart';

/// 历史页空状态提示。
class EmptyHistoryView extends StatelessWidget {
  const EmptyHistoryView({
    super.key,
    required this.hasConversations,
    required this.searchKeyword,
  });

  final bool hasConversations;
  final String searchKeyword;

  @override
  /// 构建无结果提示文本。
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasConversations && searchKeyword.trim().isNotEmpty
            ? '没有匹配“${searchKeyword.trim()}”的历史会话。'
            : '还没有可展示的历史会话。',
        textAlign: TextAlign.center,
      ),
    );
  }
}
