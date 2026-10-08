import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/date_formatting.dart';
import 'package:oh_my_llm/core/widgets/adaptive_grid/app_adaptive_grid.dart';

import '../../domain/models/favorite_collection_summary.dart';
import 'favorite_collection_tile.dart';

/// 收藏夹总览的动态网格。
///
/// 列数由父约束推导；[focusCollectionId] 指向刚新建完成的收藏夹，其卡片
/// 以 autofocus 获得可见焦点，其余场景不抢占焦点。
class FavoriteCollectionGrid extends StatelessWidget {
  const FavoriteCollectionGrid({
    required this.summaries,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    this.focusCollectionId,
    super.key,
  });

  final List<FavoriteCollectionSummary> summaries;

  /// 打开收藏夹浏览页。
  final void Function(FavoriteCollectionSummary summary) onOpen;

  /// 发起重命名（系统夹不会触发）。
  final void Function(FavoriteCollectionSummary summary) onRename;

  /// 发起删除空收藏夹（系统夹与非空夹不会触发）。
  final void Function(FavoriteCollectionSummary summary) onDelete;

  /// 需要接收焦点的收藏夹 ID。
  final String? focusCollectionId;

  @override
  Widget build(BuildContext context) {
    return AppAdaptiveGrid(
      scrollViewKey: const PageStorageKey<String>('favorite-collection-grid'),
      itemCount: summaries.length,
      maxCrossAxisExtent: 300,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      padding: const EdgeInsets.all(16),
      mainAxisExtentBuilder: _cardHeight,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = summaries.indexWhere(
          (summary) => summary.collection.id == key.value,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index, itemWidth) {
        final summary = summaries[index];
        final collection = summary.collection;
        final isSystem = collection.isSystem;
        return FavoriteCollectionTile(
          key: ValueKey<String>(collection.id),
          summary: summary,
          autofocus: collection.id == focusCollectionId,
          onOpen: () => onOpen(summary),
          onRename: isSystem ? null : () => onRename(summary),
          // 空夹删除不产生级联歧义；非空夹的去向选择由收藏夹内列表承接。
          onDelete: !isSystem && summary.itemCount == 0
              ? () => onDelete(summary)
              : null,
        );
      },
    );
  }

  double _cardHeight(BuildContext context, double itemWidth) {
    final textTheme = Theme.of(context).textTheme;
    double textHeight(String text, TextStyle? style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: math.max(0, itemWidth - AppSpacing.md * 2));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // 网格同排等高，按实际名称、身份与字号为最需要空间的卡片预留高度。
    return summaries.fold(168, (height, summary) {
      final requiredHeight =
          AppSpacing.md * 2 +
          AppInteractionSizes.minimumHitTarget +
          textHeight(
            summary.collection.name,
            textTheme.titleMedium,
            maxLines: 2,
          ) +
          (summary.collection.isSystem
              ? AppSpacing.xxs + textHeight('系统', textTheme.labelSmall)
              : 0) +
          AppSpacing.xs +
          textHeight('${summary.itemCount} 项收藏', textTheme.bodyMedium) +
          textHeight(
            formatDateOnly(summary.recentAssignedAt),
            textTheme.bodySmall,
          );
      return math.max(height, requiredHeight).ceilToDouble();
    });
  }
}
