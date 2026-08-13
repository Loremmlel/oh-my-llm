import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'media_grid_layout_spec.dart';

/// 媒体网格 tile 的尺寸计算器：给定密度规格与内容宽度，推算统一行高。
///
/// 缩略图固定 4:3，标题行数与字号随 [MediaGridTileMetrics] 的
/// `maxTitleLines` / TextScaler 变化；`mainAxisExtent` 供上游为同一行所有
/// tile 提供一致的纵向高度，保证网格对齐。
final class MediaGridTileMetrics {
  const MediaGridTileMetrics({
    required this.contentWidth,
    required this.thumbnailHeight,
    required this.titleHeight,
    required this.sizeHeight,
    required this.mainAxisExtent,
  });

  /// 缩略图与下方元数据（标题/大小）之间的纵向间距。
  static const double thumbnailMetadataGap = AppSpacing.xs;

  /// 元数据两行（标题与大小）之间的纵向间距。
  static const double metadataLineGap = AppSpacing.xxs;

  final double contentWidth;
  final double thumbnailHeight;
  final double titleHeight;
  final double sizeHeight;
  final double mainAxisExtent;

  /// 依据当前 [context] 的 Theme / TextScaler / Directionality 解析网格 tile
  /// 各段尺寸。[itemWidth] 为 tile 的总宽度，负值或无限值视为非法。
  static MediaGridTileMetrics resolve({
    required BuildContext context,
    required MediaGridLayoutSpec spec,
    required double itemWidth,
  }) {
    assert(itemWidth.isFinite && itemWidth >= 0);
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final titleStyle =
        theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final sizeStyle =
        theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final titleLineHeight = _lineHeight(titleStyle, textScaler, direction);
    final sizeLineHeight = _lineHeight(sizeStyle, textScaler, direction);
    final contentWidth = math.max(0.0, itemWidth - spec.tilePadding * 2);
    final thumbnailHeight = contentWidth / spec.thumbnailAspectRatio;
    final titleHeight = titleLineHeight * spec.maxTitleLines;
    final mainAxisExtent =
        spec.tilePadding * 2 +
        thumbnailHeight +
        thumbnailMetadataGap +
        titleHeight +
        metadataLineGap +
        sizeLineHeight;
    return MediaGridTileMetrics(
      contentWidth: contentWidth,
      thumbnailHeight: thumbnailHeight,
      titleHeight: titleHeight,
      sizeHeight: sizeLineHeight,
      mainAxisExtent: mainAxisExtent,
    );
  }

  /// 计算给定样式在当前 TextScaler 下的单行行高（用空格代理测量）。
  static double _lineHeight(
    TextStyle style,
    TextScaler textScaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: direction,
      textScaler: textScaler,
    );
    try {
      return painter.preferredLineHeight;
    } finally {
      painter.dispose();
    }
  }
}
