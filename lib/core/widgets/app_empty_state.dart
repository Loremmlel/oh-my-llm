import 'package:flutter/material.dart';

/// 通用空状态视图组件。
///
/// 由图标、标题、说明和可选操作按钮组成，垂直居中排列。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.iconSize = 42,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final double iconSize;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ConstrainedBox(minWidth: infinity) 强制撑满父级最大宽度，避免在
    // loose 宽度约束（Expanded、crossAxisAlignment.start 的 Column 子项）
    // 下 Column 只取内容宽度而整体靠左，导致水平不居中。
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: double.infinity),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          // 外层若给了 bounded 高度（如 Expanded / 固定 SizedBox），
          // 内容会垂直居中；未 bounded 时 Column 取内容高度，视觉不变。
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
