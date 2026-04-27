import 'package:flutter/material.dart';

/// 用于解释某个功能区域或初始化状态的紧凑卡片。
class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    required this.title,
    required this.description,
    required this.items,
    this.width,
    super.key,
  });

  final String title;
  final String description;
  final List<String> items;
  final double? width;

  /// 构建带标题与项目符号提示的说明面板。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
