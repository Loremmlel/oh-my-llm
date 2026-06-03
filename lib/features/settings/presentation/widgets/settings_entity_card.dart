import 'package:flutter/material.dart';

/// 设置页中各实体卡片的统一容器。
///
/// 提供统一的背景色、圆角和内边距，内部排列标题、自定义内容和操作按钮。
class SettingsEntityCard extends StatelessWidget {
  const SettingsEntityCard({
    required this.title,
    required this.body,
    required this.actions,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 标题和操作按钮之间的内容区域，每个 widget 需自带间距。
  final List<Widget> body;

  /// 底部操作按钮。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            ...body,
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
