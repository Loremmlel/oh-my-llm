import 'package:flutter/material.dart';

import '../../domain/models/favorite.dart';

/// 收藏列表中的单行条目，仅展示摘要信息。
///
/// 标题为双行：第一行取用户消息前 10 个字符，第二行取模型回复前 10 个字符，
/// 均超长截断并追加省略号。点击后由调用方导航至详情页。
class FavoriteListItem extends StatelessWidget {
  const FavoriteListItem({
    required this.favorite,
    required this.collectionName,
    required this.onTap,
    super.key,
  });

  final Favorite favorite;

  /// 所属收藏夹名称；null 表示未分类，不显示收藏夹标签。
  final String? collectionName;

  /// 点击条目时的回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userSnippet = _snippet(favorite.userMessageContent);
    final assistantSnippet = _snippet(favorite.assistantContent);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 摘要文本 ──────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userSnippet,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      assistantSnippet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // ── 元信息行：收藏夹 + 日期 ──────────────────────────────
                    DefaultTextStyle(
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (collectionName != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_outlined, size: 12),
                                const SizedBox(width: 2),
                                Text(collectionName!),
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.smart_toy_outlined, size: 12),
                              const SizedBox(width: 2),
                              Tooltip(
                                message: favorite.assistantModelDisplayName,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 160,
                                  ),
                                  child: Text(
                                    favorite.assistantModelDisplayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(_formatDate(favorite.createdAt)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── 箭头指示 ──────────────────────────────────────────────────
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 取文本前 10 个字符（按 Unicode 字符计数），超长追加省略号。
  String _snippet(String text) {
    final chars = text.characters;
    if (chars.length <= 10) return text;
    return '${chars.take(10)}…';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}
