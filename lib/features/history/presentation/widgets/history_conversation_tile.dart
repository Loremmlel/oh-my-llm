import 'package:flutter/material.dart';

import '../../../chat/domain/models/chat_conversation_summary.dart';

/// 历史页中的单个会话条目。
class HistoryConversationTile extends StatelessWidget {
  const HistoryConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRenamePressed,
    required this.onSelectionChanged,
  });

  final ChatConversationSummary conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRenamePressed;
  final ValueChanged<bool?> onSelectionChanged;

  @override
  /// 构建可选择、可重命名的会话条目。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: onSelectionChanged),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.resolvedTitle,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      conversation.previewText,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '更新时间：${conversation.updatedAt.toLocal()}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRenamePressed,
                tooltip: '重命名会话',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
