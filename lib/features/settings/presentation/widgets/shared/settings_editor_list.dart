import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 世界书与预设编辑共用条目工具栏、列表间距和滚动区域。
class SettingsEditorList extends StatelessWidget {
  const SettingsEditorList({
    required this.itemCount,
    required this.itemBuilder,
    required this.onAdd,
    this.onMoveUp,
    this.onMoveDown,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onAdd;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('条目 $itemCount', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('新增条目'),
          ),
          IconButton.outlined(
            onPressed: onMoveUp,
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: '上移',
          ),
          IconButton.outlined(
            onPressed: onMoveDown,
            icon: const Icon(Icons.arrow_downward_rounded),
            tooltip: '下移',
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: itemBuilder,
        ),
      ),
    ],
  );
}

/// 以同一选中标记呈现可编辑条目，停用等状态紧邻标题。
class SettingsEditorListTile extends StatelessWidget {
  const SettingsEditorListTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.status,
    super.key,
  });

  final String title;
  final bool selected;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: BorderDirectional(
          start: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.trim().isEmpty ? '未命名条目' : title.trim(),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(status!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
