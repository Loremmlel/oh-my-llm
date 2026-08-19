import 'package:flutter/material.dart';

/// 传输确认界面使用的摘要展示项。
final class TransferSummaryViewItem {
  const TransferSummaryViewItem({
    required this.label,
    required this.trailingText,
  });

  final String label;
  final String trailingText;
}

/// 只负责布局传输摘要，不依赖具体传输 feature 的类型。
final class TransferSummaryList extends StatelessWidget {
  const TransferSummaryList({required this.items, super.key});

  final List<TransferSummaryViewItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(item.label)),
                const SizedBox(width: 12),
                Text(
                  item.trailingText,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
