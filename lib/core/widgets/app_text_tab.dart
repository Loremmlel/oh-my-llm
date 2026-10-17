import 'package:flutter/material.dart';

/// 阅读工作区的下划线标签，共用原生按钮的键盘、焦点与禁用行为。
class AppTextTab extends StatelessWidget {
  const AppTextTab({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tab = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
    return tooltip == null ? tab : Tooltip(message: tooltip!, child: tab);
  }
}
