import 'package:flutter/material.dart';

import '../../domain/models/file_item.dart';

/// 单个文件/文件夹卡片。
///
/// 方形布局：图标（或占位图标）+ 文件名（单行省略）+ 文件大小（灰色小字）。
class MediaFileTile extends StatelessWidget {
  final FileItem item;
  final VoidCallback onTap;

  const MediaFileTile({super.key, required this.item, required this.onTap});

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
              // 图标区域
              Expanded(
                child: Icon(
                  item.isDirectory ? Icons.folder : _fileIcon(),
                  size: 48,
                  color: item.isDirectory
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
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

  IconData _fileIcon() {
    final ext = item.name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => Icons.image,
      'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' => Icons.movie,
      _ => Icons.insert_drive_file,
    };
  }
}
