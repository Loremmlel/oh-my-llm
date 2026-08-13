import 'dart:math' as math;

final class AdaptiveGridGeometry {
  const AdaptiveGridGeometry._({
    required this.crossAxisCount,
    required this.itemCrossAxisExtent,
  });

  static const double layoutTolerance = 0.5;

  final int crossAxisCount;
  final double itemCrossAxisExtent;

  factory AdaptiveGridGeometry.resolve({
    required double availableWidth,
    required double horizontalPadding,
    required double maxCrossAxisExtent,
    required double crossAxisSpacing,
  }) {
    assert(availableWidth.isFinite && availableWidth >= 0);
    assert(horizontalPadding.isFinite && horizontalPadding >= 0);
    assert(maxCrossAxisExtent.isFinite && maxCrossAxisExtent > 0);
    assert(crossAxisSpacing.isFinite && crossAxisSpacing >= 0);

    final usable = math.max(0.0, availableWidth - horizontalPadding);
    final rawCount =
        ((usable + crossAxisSpacing - layoutTolerance) /
                (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    final columns = math.max(1, rawCount);
    final itemWidth = math.max(
      0.0,
      (usable - crossAxisSpacing * (columns - 1)) / columns,
    );
    return AdaptiveGridGeometry._(
      crossAxisCount: columns,
      itemCrossAxisExtent: itemWidth,
    );
  }
}
