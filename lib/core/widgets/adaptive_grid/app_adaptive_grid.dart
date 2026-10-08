import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'adaptive_grid_geometry.dart';

typedef AppAdaptiveGridMainAxisExtentBuilder = double Function(
  BuildContext context,
  double itemCrossAxisExtent,
);
typedef AppAdaptiveGridItemBuilder = Widget Function(
  BuildContext context,
  int index,
  double itemCrossAxisExtent,
);

class AppAdaptiveGrid extends StatelessWidget {
  const AppAdaptiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.maxCrossAxisExtent,
    required this.mainAxisExtentBuilder,
    this.padding = EdgeInsets.zero,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.controller,
    this.scrollViewKey,
    this.findChildIndexCallback,
    this.equalRowHeights = true,
    super.key,
  });

  /// 少量表单卡片沿用同一列宽计算，以自然内容决定每行高度。
  /// 外层页面负责滚动，避免嵌套视口及固定卡片高度。
  AppAdaptiveGrid.content({
    required List<Widget> children,
    required this.maxCrossAxisExtent,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.equalRowHeights = true,
    super.key,
  }) : itemCount = children.length,
       itemBuilder = ((_, index, _) => children[index]),
       mainAxisExtentBuilder = null,
       padding = EdgeInsets.zero,
       controller = null,
       scrollViewKey = null,
       findChildIndexCallback = null;

  final int itemCount;
  final AppAdaptiveGridItemBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final AppAdaptiveGridMainAxisExtentBuilder? mainAxisExtentBuilder;
  final EdgeInsetsGeometry padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final ScrollController? controller;
  final Key? scrollViewKey;
  final ChildIndexGetter? findChildIndexCallback;
  final bool equalRowHeights;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final geometry = AdaptiveGridGeometry.resolve(
          availableWidth: constraints.maxWidth,
          horizontalPadding: resolvedPadding.horizontal,
          maxCrossAxisExtent: maxCrossAxisExtent,
          crossAxisSpacing: crossAxisSpacing,
        );
        final extentBuilder = mainAxisExtentBuilder;
        if (extentBuilder == null) {
          if (itemCount == 0) return const SizedBox.shrink();
          final columns = geometry.crossAxisCount;
          final itemWidth = math.min(
            maxCrossAxisExtent,
            geometry.itemCrossAxisExtent,
          );
          Widget buildRow(int start) => Row(
            crossAxisAlignment: equalRowHeights
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              for (
                var index = start;
                index < math.min(start + columns, itemCount);
                index++
              ) ...[
                if (index > start) SizedBox(width: crossAxisSpacing),
                SizedBox(
                  width: itemWidth,
                  child: itemBuilder(context, index, itemWidth),
                ),
              ],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0; start < itemCount; start += columns) ...[
                if (start > 0) SizedBox(height: mainAxisSpacing),
                if (equalRowHeights)
                  IntrinsicHeight(child: buildRow(start))
                else
                  buildRow(start),
              ],
            ],
          );
        }
        final mainAxisExtent = extentBuilder(
          context,
          geometry.itemCrossAxisExtent,
        );
        assert(mainAxisExtent.isFinite && mainAxisExtent >= 0);
        return GridView.builder(
          key: scrollViewKey,
          controller: controller,
          padding: resolvedPadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: geometry.crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: itemCount,
          findChildIndexCallback: findChildIndexCallback,
          itemBuilder: (context, index) =>
              itemBuilder(context, index, geometry.itemCrossAxisExtent),
        );
      },
    );
  }
}
