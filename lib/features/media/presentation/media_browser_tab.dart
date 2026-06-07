import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/media_browser_controller.dart';
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
              onItemTap: (item) {
                if (item.isDirectory) {
                  controller.navigateTo(item.relativePath);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
