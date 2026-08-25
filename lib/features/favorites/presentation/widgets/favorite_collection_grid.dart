import 'package:flutter/material.dart';

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
      mainAxisExtentBuilder: (context, itemWidth) => 168,
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
}
