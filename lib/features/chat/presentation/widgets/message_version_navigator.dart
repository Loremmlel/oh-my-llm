import 'package:flutter/material.dart';

/// 消息版本切换器，展示当前版本并提供前后翻页按钮。
class MessageVersionNavigator extends StatelessWidget {
  const MessageVersionNavigator({
    required this.currentIndex,
    required this.total,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final int currentIndex;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  /// 构建上一版本/下一版本的轻量导航控件。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: '上一版本',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('${currentIndex + 1}/$total', style: theme.textTheme.labelMedium),
        IconButton(
          onPressed: onNext,
          tooltip: '下一版本',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}
