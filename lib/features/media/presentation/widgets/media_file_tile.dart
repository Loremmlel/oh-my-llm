import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/media_resource_provider.dart';
import '../../application/models/media_resource_request.dart';
import '../../domain/media_file_classification.dart';
import '../../domain/models/file_item.dart';
import '../models/media_grid_layout_spec.dart';
import '../models/media_grid_tile_metrics.dart';
import 'media_image_resource_view.dart';

/// 单个文件/文件夹卡片。
///
/// 图片/视频文件：经 [mediaResourceProvider] 懒解析缩略图（本地或远端
/// 资源统一呈现）。文件夹：显示文件夹图标。
/// 其他文件：显示通用文件图标。
/// 缩略图加载失败/缺失时回退到图标显示。
/// 卡片尺寸由上游 [metrics] 固定，不再依赖 Column 弹性伸展：缩略图、
/// 标题与大小三段的固定高度累加后恰好填满统一行高，保证同一行对齐。
class MediaFileTile extends ConsumerWidget {
  final FileItem item;
  final MediaGridLayoutSpec layoutSpec;
  final MediaGridTileMetrics metrics;
  final VoidCallback onTap;

  const MediaFileTile({
    super.key,
    required this.item,
    required this.layoutSpec,
    required this.metrics,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(layoutSpec.tilePadding),
          child: Column(
            children: [
              // 缩略图 / 图标区域
              SizedBox(
                width: double.infinity,
                height: metrics.thumbnailHeight,
                child: _buildThumbnail(context, ref, theme),
              ),
              const SizedBox(height: MediaGridTileMetrics.thumbnailMetadataGap),
              // 文件名：固定标题区高度，超长省略并保留完整名称 tooltip
              SizedBox(
                height: metrics.titleHeight,
                child: Tooltip(
                  message: item.name,
                  child: Text(
                    item.name,
                    maxLines: layoutSpec.maxTitleLines,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: MediaGridTileMetrics.metadataLineGap),
              // 文件大小：无大小的项保留行高占位，维持整行对齐
              SizedBox(
                height: metrics.sizeHeight,
                child: item.formattedSize.isEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        item.formattedSize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建缩略图或图标区域。
  Widget _buildThumbnail(BuildContext context, WidgetRef ref, ThemeData theme) {
    // 文件夹 → 图标
    if (item.isDirectory) {
      return Icon(Icons.folder, size: 48, color: theme.colorScheme.primary);
    }

    // 无缩略图信号 → 图标
    if (!item.hasThumbnail) return _fallbackIcon(theme);

    final request = MediaThumbnailRequest(
      relativePath: item.relativePath,
      sizeBytes: item.sizeBytes,
      lastModified: item.lastModified,
      hasThumbnail: item.hasThumbnail,
    );
    final resource = ref.watch(mediaResourceProvider(request));
    // Riverpod 3 的 FutureProvider 失败时状态是「带错误附着的 loading」，
    // 必须先按 hasError 判定，否则错误会被当成加载中
    if (resource.hasError) return _fallbackIcon(theme);
    final resourceValue = switch (resource) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (resourceValue == null) {
      // 加载中与解析为 null 均属「暂无数据」，统一先显示回退图标、
      // 不区分中间态；数据就绪后由 MediaImageResourceView 替换显示
      return _fallbackIcon(theme);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: MediaImageResourceView(
        resource: resourceValue,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  /// 缩略图不可用时的回退图标。
  Widget _fallbackIcon(ThemeData theme) {
    return Icon(
      _fileIcon(),
      size: 48,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  IconData _fileIcon() {
    if (isImageFile(item.name)) return Icons.image;
    if (isVideoFile(item.name)) return Icons.movie;
    return Icons.insert_drive_file;
  }
}
