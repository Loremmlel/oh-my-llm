import 'package:flutter/material.dart';

import '../../../chat/presentation/widgets/reasoning_panel.dart';
import '../../../chat/presentation/widgets/streaming_markdown_view.dart';
import '../../domain/models/favorite.dart';

/// 单条收藏卡片，展示用户消息、模型回复和来源元信息。
class FavoriteCard extends StatelessWidget {
  const FavoriteCard({
    required this.favorite,
    required this.collectionName,
    required this.onDeletePressed,
    required this.onGoToConversation,
    super.key,
  });

  final Favorite favorite;

  /// 所属收藏夹名称，null 表示未分类。
  final String? collectionName;

  /// 删除该收藏记录。
  final VoidCallback onDeletePressed;

  /// 跳转到来源对话；当来源对话不存在时为 null。
  final VoidCallback? onGoToConversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 元信息行 ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (collectionName != null) ...[
                        Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        Text(
                          collectionName!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(
                        _formatDate(favorite.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onGoToConversation != null)
                  Flexible(
                    child: Tooltip(
                      message: '跳转到来源对话',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: onGoToConversation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              if (favorite.sourceConversationTitle != null &&
                                  favorite.sourceConversationTitle!
                                      .trim()
                                      .isNotEmpty) ...[
                                Expanded(
                                  child: Text(
                                    favorite.sourceConversationTitle!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 2),
                              ],
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: onDeletePressed,
                  tooltip: '删除收藏',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 用户消息 ───────────────────────────────────────────────────
            if (favorite.userMessageContent.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  favorite.userMessageContent,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── 推理内容（可折叠） ──────────────────────────────────────────
            if (favorite.hasReasoning) ...[
              ReasoningPanel(content: favorite.assistantReasoningContent),
              const SizedBox(height: 8),
            ],

            // ── 模型回复 ───────────────────────────────────────────────────
            StreamingMarkdownView(
              content: favorite.assistantContent,
              isStreaming: false,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
