import 'package:flutter/material.dart';

import '../../data/media_mime_types.dart';
import '../../utils/path_utils.dart';
import '../../domain/models/file_item.dart';

/// 单个文件/文件夹卡片。
///
/// 图片/视频文件：显示缩略图（从服务端 `thumbnailUrl` 懒加载）。
/// 文件夹：显示文件夹图标。
/// 其他文件：显示通用文件图标。
/// 缩略图加载失败时回退到图标显示。
class MediaFileTile extends StatelessWidget {
  final FileItem item;
  /// 缩略图服务端 base URL（如 "http://192.168.1.5:12345"）。
  /// 为 null 时不请求缩略图（回退到图标模式）。
  final String? thumbnailBaseUrl;
  final VoidCallback onTap;

  const MediaFileTile({
    super.key,
    required this.item,
    this.thumbnailBaseUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: _buildThumbnail(theme),
              ),
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
  Widget _buildThumbnail(ThemeData theme) {
    // 文件夹 → 图标
    if (item.isDirectory) {
      return Icon(
        Icons.folder,
        size: 48,
        color: theme.colorScheme.primary,
      );
    }

    // 有缩略图 URL 且 base URL 已提供 → Image.network
    final fullUrl = _thumbnailFullUrl();
    if (fullUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          fullUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              _fallbackIcon(theme),
        ),
      );
    }

    // 无缩略图 → 图标
    return _fallbackIcon(theme);
  }

  /// 构建缩略图完整 URL。
  String? _thumbnailFullUrl() {
    if (item.thumbnailUrl == null || thumbnailBaseUrl == null) return null;
    final url = item.thumbnailUrl!;
    // item.thumbnailUrl 如 "/api/media/thumbnail/sister/视频/cat.mp4"（未编码）
    const prefix = '/api/media/thumbnail/';
    if (!url.startsWith(prefix)) return '$thumbnailBaseUrl$url';
    final path = url.substring(prefix.length);
    return '$thumbnailBaseUrl$prefix${encodeMediaPath(path)}';
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
