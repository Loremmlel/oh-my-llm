import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/widgets/adaptive_grid/adaptive_grid_geometry.dart';

/// 收藏夹网格的布局规格：限宽、间距、内边距与固定卡片高度。
///
/// 列数由父约束经 [AdaptiveGridGeometry] 推导，不绑定设备类型；
/// 卡片主轴高度固定，保证同一行所有卡片的图标、名称、数量与时间行对齐。
final class FavoriteCollectionGridSpec {
  const FavoriteCollectionGridSpec({
    this.maxCrossAxisExtent = 300,
    this.spacing = 16,
    this.padding = const EdgeInsets.all(16),
    this.tilePadding = 16,
    this.mainAxisExtent = 168,
  });

  /// 单张卡片的期望最大宽度；父约束更宽时由列数分摊。
  final double maxCrossAxisExtent;

  /// 卡片之间与网格四周的间距。
  final double spacing;
  final EdgeInsets padding;

  /// 卡片内部留白。
  final double tilePadding;

  /// 固定卡片高度：图标行 + 两行名称 + 数量与最近收录时间元信息。
  final double mainAxisExtent;

  /// 给定网格可用宽度推导列数，供测试锁定响应式契约。
  int crossAxisCountForWidth(double availableWidth) {
    return AdaptiveGridGeometry.resolve(
      availableWidth: availableWidth,
      horizontalPadding: padding.horizontal,
      maxCrossAxisExtent: maxCrossAxisExtent,
      crossAxisSpacing: spacing,
    ).crossAxisCount;
  }
}
