import 'package:flutter/material.dart';

/// 用于尚未启用功能页的居中占位卡片。
class FeaturePlaceholderView extends StatelessWidget {
  const FeaturePlaceholderView({
    required this.title,
    required this.description,
    required this.highlights,
    super.key,
  });

  final String title;
  final String description;
  final List<String> highlights;

  /// 构建一个友好的占位说明，并列出关键提示。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Oh My LLM', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(description, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  for (final item in highlights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
