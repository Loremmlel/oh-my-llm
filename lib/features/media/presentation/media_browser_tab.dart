import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/media_browser_controller.dart';
import '../data/media_mime_types.dart';
import 'pages/image_viewer_page.dart';
import 'pages/video_player_page.dart';
import 'widgets/media_grid_view.dart';
import 'widgets/media_path_bar.dart';

/// 媒体浏览器 Tab 内容组件。
///
/// 提供目录浏览、路径导航和返回键处理。
/// [onExitMediaBrowser] 在根目录按返回键时调用，用于切回同步连接 Tab。
class MediaBrowserTab extends ConsumerStatefulWidget {
  final VoidCallback onExitMediaBrowser;

  const MediaBrowserTab({super.key, required this.onExitMediaBrowser});

  @override
  ConsumerState<MediaBrowserTab> createState() => _MediaBrowserTabState();
}

class _MediaBrowserTabState extends ConsumerState<MediaBrowserTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mediaBrowserControllerProvider);
    final controller = ref.read(mediaBrowserControllerProvider.notifier);
    final server = state.server;

    // 构建缩略图 base URL（server 未就绪时为 null，回退到图标模式）
    final thumbnailBase = (server != null)
        ? 'http://${server.ip}:${server.httpPort}'
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canGoBack = await controller.goBack();
        if (!canGoBack) {
          widget.onExitMediaBrowser();
        }
      },
      child: Column(
        children: [
          // 路径导航栏
          MediaPathBar(
            currentPath: state.currentPath,
            onPathSelected: (path) => controller.navigateTo(path),
          ),
          const Divider(height: 1),
          // 内容区域
          Expanded(
            child: MediaGridView(
              items: state.items,
              isLoading: state.isLoading,
              errorMessage: state.errorMessage,
              thumbnailBaseUrl: thumbnailBase,
              onItemTap: (item) {
                if (item.isDirectory) {
                  controller.navigateTo(item.relativePath);
                } else if (isImageFile(item.name)) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImageViewerPage(
                        imageUrl: _buildMediaUrl('image', item.relativePath),
                        fileName: item.name,
                      ),
                    ),
                  );
                } else if (isVideoFile(item.name)) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerPage(
                        videoUrl: _buildMediaUrl('video', item.relativePath),
                        fileName: item.name,
                      ),
                    ),
                  );
                }
                // 其他类型文件：无操作
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建媒体资源访问 URL。
  ///
  /// 路径每段单独编码以支持中文。
  /// 返回空字符串若 server 未就绪（防御性编程）。
  String _buildMediaUrl(String type, String relativePath) {
    final server = ref.read(mediaBrowserControllerProvider).server;
    if (server == null) return '';
    final encodedPath = encodeMediaPath(relativePath);
    return 'http://${server.ip}:${server.httpPort}/api/media/$type/$encodedPath';
  }
}
