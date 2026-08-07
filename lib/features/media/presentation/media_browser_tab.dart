import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import '../application/media_browser_controller.dart';
import '../application/shuffle_playback_controller.dart';
import '../domain/media_file_classification.dart';
import 'widgets/media_grid_view.dart';
import 'widgets/media_path_bar.dart';

/// 媒体浏览器 Tab 内容组件。
///
/// 提供目录浏览、路径导航和返回键处理。
/// TabBarView 离屏保留本组件不代表媒体页面会话仍有效；会话边界由
/// app composition 在切离媒体 Tab 时统一 reset。
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
    // 监听目录切换 -> 清空随机播放列表
    ref.listen<MediaBrowserState>(mediaBrowserControllerProvider, (prev, next) {
      if (prev != null && prev.currentPath != next.currentPath) {
        ref
            .read(shufflePlaybackControllerProvider.notifier)
            .clearIfDirectoryChanged(next.currentPath);
      }
    });
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
                  // server 缺失时不导航，保持原有防御行为；
                  // 图片/视频 URL 由 routed page 从可信会话重建。
                  if (state.server == null) return;
                  context.pushNamed(
                    AppRouteName.mediaImage,
                    queryParameters: {
                      AppRouteParameter.mediaPath: item.relativePath,
                    },
                  );
                } else if (isVideoFile(item.name)) {
                  if (state.server == null) return;
                  context.pushNamed(
                    AppRouteName.mediaVideo,
                    queryParameters: {
                      AppRouteParameter.mediaPath: item.relativePath,
                    },
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
}
