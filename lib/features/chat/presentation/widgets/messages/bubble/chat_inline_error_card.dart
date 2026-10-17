import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/widgets/app_inline_notice.dart';

/// 聊天消息气泡内的内联错误提示卡片。
class ChatInlineErrorCard extends StatelessWidget {
  const ChatInlineErrorCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppInlineNotice(
      message: message,
      color: theme.colorScheme.error,
      icon: Icons.error_outline,
    );
  }
}
