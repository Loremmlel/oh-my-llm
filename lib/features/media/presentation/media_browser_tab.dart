import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import '../application/media_browser_controller.dart';
import '../application/media_library_session_controller.dart';
import '../application/shuffle_playback_controller.dart';
import '../domain/media_file_classification.dart';
import 'widgets/media_grid_view.dart';
import 'widgets/media_path_bar.dart';

/// 媒体浏览器 Tab 内容组件。
///
/// 提供目录浏览与路径导航，不处理系统返回键：媒体 Tab 是否可见由
/// app composition 的 SyncWorkspaceScreen 裁定并声明本地返回目标，
/// presentation leaf 自行拦截返回会把消费与 Tab 可见性解耦。
/// TabBarView 离屏保留本组件不代表媒体页面会话仍有效；会话边界由
/// app composition 在切离媒体 Tab 时统一 reset。
/// [onExitMediaBrowser] 供错误/失效会话的显式「返回连接」按钮调用。
class MediaBrowserTab extends ConsumerStatefulWidget {
  final VoidCallback onExitMediaBrowser;

  const MediaBrowserTab({super.key, required this.onExitMediaBrowser});

  @override
  ConsumerState<MediaBrowserTab> createState() => _MediaBrowserTabState();
}

class _MediaBrowserTabState extends ConsumerState<MediaBrowserTab> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mediaLibrarySessionProvider);
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

    return switch (session) {
      MediaLibrarySessionOpening() => const Center(
        child: CircularProgressIndicator(),
      ),
      MediaLibrarySessionFailed(:final failure) => AppEmptyState(
        icon: Icons.link_off_rounded,
        title: failure.message,
        description: '请返回同步页重新打开媒体浏览器。',
        action: FilledButton(
          // 返回按钮切回「连接」Tab，用户在此重新配置根目录或连接服务端
          onPressed: widget.onExitMediaBrowser,
          child: const Text('返回连接'),
        ),
      ),
      MediaLibrarySessionInactive() => const AppEmptyState(
        icon: Icons.perm_media,
        title: '媒体会话不可用',
        description: '请返回同步页重新打开媒体浏览器。',
      ),
      MediaLibrarySessionActive() => _buildBrowser(context, state, controller),
    };
  }

  /// 活动会话下的浏览界面：路径栏 + 目录网格。
  ///
  /// 目录点击只改变控制器路径；媒体文件点击按相对路径 push 子路由，
  /// 资源的实际解析由 routed page 从当前会话懒执行。
  Widget _buildBrowser(
    BuildContext context,
    MediaBrowserState state,
    MediaBrowserController controller,
  ) {
    return Column(
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
              } else if (isImageFile(item.name)) {
                context.pushNamed(
                  AppRouteName.mediaImage,
                  queryParameters: {
                    AppRouteParameter.mediaPath: item.relativePath,
                  },
                );
              } else if (isVideoFile(item.name)) {
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
    );
  }
}
