import 'package:flutter/material.dart';

/// 设置页卡片集合的统一响应式排布。
///
/// 在宽屏下按规整网格分行，并通过 [IntrinsicHeight] 让同一行卡片高度一致；
/// 在紧凑布局下回退为单列，避免内容被压得过窄。
class SettingsCardGrid extends StatelessWidget {
  const SettingsCardGrid({
    required this.children,
    super.key,
    this.minItemWidth = 280,
    this.maxColumns = 3,
    this.gap = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            ((constraints.maxWidth + gap) / (minItemWidth + gap)).floor().clamp(
              1,
              maxColumns,
            );
        if (crossAxisCount == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index += 1) ...[
                children[index],
                if (index != children.length - 1) SizedBox(height: gap),
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += crossAxisCount) {
          final rowChildren = children
              .skip(start)
              .take(crossAxisCount)
              .toList(growable: false);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < crossAxisCount; index += 1) ...[
                    if (index > 0) SizedBox(width: gap),
                    Expanded(
                      child: SizedBox.expand(
                        child: index < rowChildren.length
                            ? rowChildren[index]
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index += 1) ...[
              rows[index],
              if (index != rows.length - 1) SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }
}
