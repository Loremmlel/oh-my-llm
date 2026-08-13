import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/adaptive_grid/app_adaptive_grid.dart';

import '../../application/media_grid_density_controller.dart';
import '../../domain/models/file_item.dart';
import '../models/media_grid_layout_spec.dart';
import '../models/media_grid_tile_metrics.dart';
import 'media_file_tile.dart';

/// 媒体文件网格视图。
///
/// 列数由父级可用宽度经 [AppAdaptiveGrid] 推导，不再固定三列；卡片尺寸与
/// 统一行高由当前密度的 [MediaGridLayoutSpec] 与 [MediaGridTileMetrics] 解析，
/// 同一行所有 tile 保持同一纵向高度。
/// 内置 loading / error / empty 三种状态。
class MediaGridView extends ConsumerWidget {
  final List<FileItem> items;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<FileItem> onItemTap;

  const MediaGridView({
    super.key,
    required this.items,
    required this.isLoading,
    this.errorMessage,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.xs),
            Text(errorMessage!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 48),
            SizedBox(height: AppSpacing.xs),
            Text('目录为空'),
          ],
        ),
      );
    }

    final density = ref.watch(mediaGridDensityProvider);
    final spec = MediaGridLayoutSpec.forDensity(density);
    return AppAdaptiveGrid(
      scrollViewKey: const PageStorageKey<String>('media-grid'),
      itemCount: items.length,
      maxCrossAxisExtent: spec.maxCrossAxisExtent,
      crossAxisSpacing: spec.spacing,
      mainAxisSpacing: spec.spacing,
      padding: spec.padding,
      mainAxisExtentBuilder: (context, itemWidth) =>
          MediaGridTileMetrics.resolve(
            context: context,
            spec: spec,
            itemWidth: itemWidth,
          ).mainAxisExtent,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = items.indexWhere(
          (item) => item.relativePath == key.value,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index, itemWidth) {
        final item = items[index];
        final metrics = MediaGridTileMetrics.resolve(
          context: context,
          spec: spec,
          itemWidth: itemWidth,
        );
        return MediaFileTile(
          key: ValueKey<String>(item.relativePath),
          item: item,
          layoutSpec: spec,
          metrics: metrics,
          onTap: () => onItemTap(item),
        );
      },
    );
  }
}
