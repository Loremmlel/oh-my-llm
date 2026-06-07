import 'package:flutter/material.dart';

import '../../domain/models/file_item.dart';
import 'media_file_tile.dart';

/// 媒体文件网格视图。
///
/// 按 PRD 需求：固定方形卡片、不采用瀑布流/交错布局。
/// 内置 loading / error / empty 三种状态。
class MediaGridView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
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
            SizedBox(height: 8),
            Text('目录为空'),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaFileTile(
          item: item,
          onTap: () => onItemTap(item),
        );
      },
    );
  }
}
