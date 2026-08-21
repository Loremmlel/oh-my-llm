import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import '../../domain/models/favorite.dart';

/// 收藏夹分页列表中的单行条目。
///
/// 宽侧（父约束达到 [AppBreakpoints.contentMasterDetail]）把模型与收藏时间
/// 放到右侧元信息列；窄侧在摘要下方纵向堆叠同一组信息。标题与回复预览
/// 最多两行、超长省略，不做定长截断。夹内列表不重复展示所属收藏夹名。
class FavoriteListItem extends StatelessWidget {
  const FavoriteListItem({
    required this.favorite,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onSelectToggle,
    required this.onMoveRequested,
    required this.onDeleteRequested,
    super.key,
  });

  final Favorite favorite;

  /// 是否处于选择模式：点击行为切换为勾选。
  final bool selectionMode;

  /// 选择模式下该行是否被勾选。
  final bool selected;

  /// 打开详情（非选择模式的普通点击）。
  final VoidCallback onTap;

  /// 切换该行勾选状态（选择模式点击 / Ctrl 点击 / 长按进入）。
  final VoidCallback onSelectToggle;

  /// 发起移动该条收藏。
  final VoidCallback onMoveRequested;

  /// 发起删除该条收藏。
  final VoidCallback onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = favorite.displayTitle;
    final previewText = favorite.assistantContent.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode ? onSelectToggle : onTap,
        onLongPress: selectionMode ? null : onSelectToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide =
                  constraints.maxWidth >= AppBreakpoints.contentMasterDetail;
              final metaColor = theme.colorScheme.onSurfaceVariant;

              final modelMeta = _MetaLabel(
                icon: Icons.smart_toy_outlined,
                text: favorite.assistantModelDisplayName,
              );
              final timeMeta = _MetaLabel(
                icon: Icons.schedule_rounded,
                text: formatDateTime(favorite.createdAt),
              );

              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      previewText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: metaColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // 窄侧：模型与时间并入摘要下方一行；宽侧由右侧元信息列承担。
                  if (!isWide) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [modelMeta, timeMeta],
                    ),
                  ],
                ],
              );

              return Row(
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: selected ? theme.colorScheme.primary : metaColor,
                      ),
                    ),
                  Expanded(child: summary),
                  if (isWide && !selectionMode) ...[
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        modelMeta,
                        const SizedBox(height: 4),
                        timeMeta,
                      ],
                    ),
                  ],
                  if (!selectionMode)
                    _RowOverflowMenu(
                      onSelectRequested: onSelectToggle,
                      onMoveRequested: onMoveRequested,
                      onDeleteRequested: onDeleteRequested,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 图标 + 单行文本的小型元信息标签。
class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Tooltip(
            message: text,
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// 行尾溢出菜单：提供选择、移动与删除入口。
class _RowOverflowMenu extends StatelessWidget {
  const _RowOverflowMenu({
    required this.onSelectRequested,
    required this.onMoveRequested,
    required this.onDeleteRequested,
  });

  final VoidCallback onSelectRequested;
  final VoidCallback onMoveRequested;
  final VoidCallback onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(onPressed: onSelectRequested, child: const Text('选择')),
        MenuItemButton(onPressed: onMoveRequested, child: const Text('移动')),
        MenuItemButton(onPressed: onDeleteRequested, child: const Text('删除')),
      ],
      builder: (context, controller, child) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        tooltip: '更多操作',
        icon: const Icon(Icons.more_vert),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
