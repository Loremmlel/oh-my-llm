import 'package:flutter/material.dart';

/// Chat 与 Agent 共用的轻量返回最新入口。
class AppScrollToLatestButton extends StatelessWidget {
  const AppScrollToLatestButton({
    required this.onPressed,
    this.tooltip = '回到最新',
    super.key,
  });
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
