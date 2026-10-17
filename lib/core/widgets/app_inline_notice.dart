import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 轻量原位反馈，文字与图标共同表达状态，不覆盖整块阅读画布。
class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    required this.message,
    required this.color,
    required this.icon,
    super.key,
  });
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: color, width: 2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
