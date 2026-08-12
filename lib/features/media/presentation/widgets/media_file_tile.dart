import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/media/application/media_resource_provider.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import '../../domain/media_file_classification.dart';
import '../../domain/models/file_item.dart';
import 'media_image_resource_view.dart';

/// 单个文件/文件夹卡片。
///
/// 图片/视频文件：经 [mediaResourceProvider] 懒解析缩略图（本地或远端
/// 资源统一呈现）。文件夹：显示文件夹图标。
/// 其他文件：显示通用文件图标。
/// 缩略图加载失败/缺失时回退到图标显示。
class MediaFileTile extends ConsumerWidget {
  final FileItem item;
  final VoidCallback onTap;

  const MediaFileTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 缩略图 / 图标区域
              Expanded(child: _buildThumbnail(context, ref, theme)),
              const SizedBox(height: 4),
              // 文件名
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              // 文件大小
              if (item.formattedSize.isNotEmpty)
                Text(
                  item.formattedSize,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
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
      // 加载中显示细进度条；缩略图缺失显示回退图标
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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
