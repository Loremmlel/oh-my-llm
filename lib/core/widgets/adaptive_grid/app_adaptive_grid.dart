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
    super.key,
  });

  final int itemCount;
  final AppAdaptiveGridItemBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final AppAdaptiveGridMainAxisExtentBuilder mainAxisExtentBuilder;
  final EdgeInsetsGeometry padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final ScrollController? controller;
  final Key? scrollViewKey;
  final ChildIndexGetter? findChildIndexCallback;

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
        final mainAxisExtent = mainAxisExtentBuilder(
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
