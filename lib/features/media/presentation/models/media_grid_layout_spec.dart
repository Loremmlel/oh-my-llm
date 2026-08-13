import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';

/// 每个媒体密度对应的网格布局规格：限宽、间距、内边距与标题行数。
///
/// 缩略图区域固定 4:3；每轮布局由 [MediaGridTileMetrics] 为所有 tile 提供
/// 同一个 `mainAxisExtent`，保证同一行高度统一。
final class MediaGridLayoutSpec {
  const MediaGridLayoutSpec({
    required this.maxCrossAxisExtent,
    required this.spacing,
    required this.padding,
    required this.tilePadding,
    required this.thumbnailAspectRatio,
    required this.maxTitleLines,
  });

  final double maxCrossAxisExtent;
  final double spacing;
  final EdgeInsets padding;
  final double tilePadding;
  final double thumbnailAspectRatio;
  final int maxTitleLines;

  static MediaGridLayoutSpec forDensity(AppLayoutDensity density) =>
      switch (density) {
        AppLayoutDensity.compact => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 160,
          spacing: 8,
          padding: EdgeInsets.all(8),
          tilePadding: 8,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 1,
        ),
        AppLayoutDensity.standard => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 220,
          spacing: 12,
          padding: EdgeInsets.all(12),
          tilePadding: 12,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 2,
        ),
        AppLayoutDensity.comfortable => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 360,
          spacing: 16,
          padding: EdgeInsets.all(16),
          tilePadding: 16,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 2,
        ),
      };
}
