import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

/// 历史页中的单个会话条目。
///
/// 普通态：整行点击导航，行尾 overflow 提供选择/重命名/删除，
/// 右键与菜单键可打开等价上下文菜单；不常驻 checkbox。
/// 选择态：整行点击切换选择，行首 checkbox 反映选中状态供读屏识别。
class HistoryConversationTile extends StatelessWidget {
  const HistoryConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectRequested,
    required this.onRenameRequested,
    required this.onDeleteRequested,
    this.contextMenuKey,
  });

  final ChatConversationSummary conversation;
  final bool selected;

  /// 当前是否处于选择模式。
  final bool selectionMode;

  /// 整行点击（含修饰键判定）由 screen 处理。
  final VoidCallback onTap;

  /// 长按（进入选择）。
  final VoidCallback onLongPress;

  /// overflow / 上下文菜单动作。
  final VoidCallback onSelectRequested;
  final VoidCallback onRenameRequested;
  final VoidCallback onDeleteRequested;

  /// 定位上下文菜单锚点用的 key；由 screen 持有以支持菜单键。
  final Key? contextMenuKey;

  List<PopupMenuItem<String>> _buildMenuItems(bool selectionMode) => [
    PopupMenuItem(value: 'select', child: Text(selectionMode ? '取消选择' : '选择')),
    const PopupMenuItem(value: 'rename', child: Text('重命名')),
    const PopupMenuItem(value: 'delete', child: Text('删除')),
  ];

  void _handleMenuAction(String action, {required BuildContext context}) {
    switch (action) {
      case 'select':
        onSelectRequested();
      case 'rename':
        onRenameRequested();
      case 'delete':
        onDeleteRequested();
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: _buildMenuItems(selectionMode),
    ).then((action) {
      if (action == null || !context.mounted) return;
      _handleMenuAction(action, context: context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      key: contextMenuKey,
      selected: selected,
      container: true,
      label: conversation.resolvedTitle,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth /
                        MediaQuery.textScalerOf(context).scale(1) >=
                    AppBreakpoints.contentMasterDetail;
                final date = Text(
                  formatDateTime(conversation.updatedAt.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectionMode) ...[
                      Checkbox(
                        value: selected,
                        onChanged: (_) => onSelectRequested(),
                      ),
                      const SizedBox(width: 8),
                    ],
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
                          if (!conversation.hasCustomTitle) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              conversation.previewText,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (!wide) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            date,
                          ],
                        ],
                      ),
                    ),
                    if (wide) ...[const SizedBox(width: AppSpacing.lg), date],
                    const SizedBox(width: AppSpacing.sm),
                    PopupMenuButton<String>(
                      tooltip: '更多操作',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (action) =>
                          _handleMenuAction(action, context: context),
                      itemBuilder: (_) => _buildMenuItems(selectionMode),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
