import 'package:flutter/material.dart';

/// 聊天消息气泡内的内联错误提示卡片。
class ChatInlineErrorCard extends StatelessWidget {
  const ChatInlineErrorCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.72),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
            fontFamilyFallback: const ['monospace'],
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
