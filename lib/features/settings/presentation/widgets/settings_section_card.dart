import 'package:flutter/material.dart';

/// 设置页中用于包裹单个配置区域的统一卡片。
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    required this.description,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? action;

  @override
  /// 构建带标题、说明和可选操作按钮的设置卡片。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(description, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 16), action!],
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
