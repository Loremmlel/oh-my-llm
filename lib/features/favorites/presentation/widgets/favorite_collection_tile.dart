import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import '../../domain/models/favorite_collection_summary.dart';
import '../models/favorite_collection_grid_spec.dart';

/// 打开当前聚焦卡片上下文菜单的内部 intent；
/// 由 Menu key 与 Shift+F10 触发，作为鼠标右键的键盘等价操作。
class _OpenTileMenuIntent extends Intent {
  const _OpenTileMenuIntent();
}

/// 收藏夹总览网格中的单张收藏夹卡片。
///
/// 卡片高度由 [FavoriteCollectionGridSpec.mainAxisExtent] 固定；普通卡片
/// 提供点击/Enter 打开与右键、长按、Menu key 呼出的管理菜单；系统收藏夹
/// 只保留低调的身份标识，不提供任何管理操作。
class FavoriteCollectionTile extends StatefulWidget {
  const FavoriteCollectionTile({
    required this.summary,
    required this.spec,
    required this.onOpen,
    this.onRename,
    this.onDelete,
    this.autofocus = false,
    super.key,
  });

  final FavoriteCollectionSummary summary;
  final FavoriteCollectionGridSpec spec;

  /// 打开该收藏夹的浏览页。
  final VoidCallback onOpen;

  /// 发起重命名；为 null 时菜单不提供该项。
  final VoidCallback? onRename;

  /// 发起删除；为 null 时菜单不提供该项。
  final VoidCallback? onDelete;

  /// 新建完成后由网格对目标卡片置 true，让新卡获得可见焦点。
  final bool autofocus;

  @override
  State<FavoriteCollectionTile> createState() => _FavoriteCollectionTileState();
}

class _FavoriteCollectionTileState extends State<FavoriteCollectionTile> {
  final MenuController _menuController = MenuController();

  bool get _hasMenu =>
      widget.summary.collection.isSystem == false &&
      (widget.onRename != null || widget.onDelete != null);

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
      return;
    }
    _menuController.open();
  }

  void _openMenuAt(Offset localPosition) {
    _menuController.open(position: localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collection = widget.summary.collection;
    final isSystem = collection.isSystem;

    final card = Tooltip(
      message: collection.name,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onOpen,
          onLongPress: _hasMenu ? _toggleMenu : null,
          onSecondaryTapUp: _hasMenu
              ? (details) => _openMenuAt(details.localPosition)
              : null,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: EdgeInsets.all(widget.spec.tilePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSystem
                          ? Icons.folder_special_rounded
                          : Icons.folder_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const Spacer(),
                    if (_hasMenu)
                      IconButton(
                        onPressed: _toggleMenu,
                        tooltip: '更多操作',
                        icon: const Icon(Icons.more_vert),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                Text(
                  collection.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (isSystem)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      '系统',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  '${widget.summary.itemCount} 项收藏',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  formatDateOnly(widget.summary.recentAssignedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!_hasMenu) {
      return card;
    }

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        if (widget.onRename != null)
          MenuItemButton(onPressed: widget.onRename, child: const Text('重命名')),
        if (widget.onDelete != null)
          MenuItemButton(
            onPressed: widget.onDelete,
            child: const Text('删除收藏夹'),
          ),
      ],
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.contextMenu):
              _OpenTileMenuIntent(),
          SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _OpenTileMenuIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _OpenTileMenuIntent: CallbackAction<_OpenTileMenuIntent>(
              onInvoke: (_) {
                _menuController.open();
                return null;
              },
            ),
          },
          child: card,
        ),
      ),
    );
  }
}
