import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/utils/date_formatting.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/reasoning_panel.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/messages/bubble/streaming_markdown_view.dart';

import '../../domain/models/favorite.dart';

/// 单条收藏卡片：元信息行 + 用户消息、折叠推理与 Markdown 模型回复。
///
/// 只负责内容渲染；重命名/移动/删除等操作由页面层的溢出菜单承担，
/// 收藏夹入口通过 [onCollectionTap] 上抛导航意图。
class FavoriteCard extends StatelessWidget {
  const FavoriteCard({
    required this.favorite,
    required this.collectionName,
    this.onCollectionTap,
    super.key,
  });

  final Favorite favorite;

  /// 所属收藏夹名称，null 表示归属信息暂不可得。
  final String? collectionName;

  /// 点击所属收藏夹入口；为 null 时入口不可交互。
  final VoidCallback? onCollectionTap;

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
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 所属收藏夹入口：可点击跳转到对应收藏夹列表。
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onCollectionTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: onCollectionTap != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          collectionName ?? '未分类',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onCollectionTap != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatDateTime(favorite.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: favorite.assistantModelDisplayName,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          favorite.assistantModelDisplayName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
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
}
