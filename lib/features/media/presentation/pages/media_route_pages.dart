import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import '../../application/media_browser_controller.dart';
import '../../domain/media_file_classification.dart';
import '../../utils/path_utils.dart';
import 'image_viewer_page.dart';
import 'video_player_page.dart';

/// 图片查看的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，结合当前可信媒体会话重建
/// [ImageViewerPage]；参数缺失/非法或会话失效时展示恢复页。
/// 不读取 route 中的 host/port，网络 authority 只来自已连接会话。
class MediaImageRoutePage extends ConsumerWidget {
  const MediaImageRoutePage({required this.relativePath, super.key});

  final String? relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = normalizeMediaRoutePath(relativePath);
    if (normalized == null || !isImageFile(_fileNameOf(normalized))) {
      return const MediaRouteRecoveryPage(routeTitle: '图片查看', reason: '媒体链接无效');
    }

    final browser = ref.watch(mediaBrowserControllerProvider);
    final server = browser.server;
    if (server == null) {
      return const MediaRouteRecoveryPage(
        routeTitle: '图片查看',
        reason: '媒体会话已失效',
      );
    }

    final imageItems = browser.items
        .where((i) => isImageFile(i.name))
        .toList(growable: false);
    final targetIndex = imageItems.indexWhere(
      (i) => i.relativePath == normalized,
    );

    if (targetIndex >= 0) {
      // 目标在当前目录图片列表中：按当前 items 顺序恢复画廊。
      return ImageViewerPage(
        imageUrls: [
          for (final item in imageItems)
            buildMediaResourceUrl(server, 'image', item.relativePath),
        ],
        initialIndex: targetIndex,
      );
    }

    // 目标不在当前列表（direct link/rebuild 时列表未恢复）：单图查看，
    // 资源已删除时由 leaf page 的 broken-image 状态呈现，仍可返回。
    return ImageViewerPage(
      imageUrls: [buildMediaResourceUrl(server, 'image', normalized)],
    );
  }
}

/// 视频播放的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，结合可信 server 重建 [VideoPlayerPage]；
/// [controllerFactory] 仅作测试注入的播放器平台替换，不进入 route state。
class MediaVideoRoutePage extends ConsumerWidget {
  const MediaVideoRoutePage({
    required this.relativePath,
    this.controllerFactory,
    super.key,
  });

  final String? relativePath;
  final VideoPlayerController Function(Uri)? controllerFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = normalizeMediaRoutePath(relativePath);
    if (normalized == null || !isVideoFile(_fileNameOf(normalized))) {
      return const MediaRouteRecoveryPage(routeTitle: '视频播放', reason: '媒体链接无效');
    }

    final server = ref.watch(mediaBrowserControllerProvider).server;
    if (server == null) {
      return const MediaRouteRecoveryPage(
        routeTitle: '视频播放',
        reason: '媒体会话已失效',
      );
    }

    // 随机播放列表来自递归接口，当前目录 items 不一定包含目标，
    // 因此不要求用 state.items 验证视频存在。
    return VideoPlayerPage(
      videoUrl: buildMediaResourceUrl(server, 'video', normalized),
      fileName: _fileNameOf(normalized),
      controllerFactory: controllerFactory,
    );
  }
}

/// 媒体路由恢复页：参数或会话失效时的可返回页面级状态。
///
/// 不自动 redirect：让用户看到失效原因，同时支持 push 后的 pop
/// 与 deep link 直达时的 go 回退。
class MediaRouteRecoveryPage extends StatelessWidget {
  const MediaRouteRecoveryPage({
    required this.routeTitle,
    required this.reason,
    super.key,
  });

  final String routeTitle;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(routeTitle)),
      body: AppEmptyState(
        icon: Icons.link_off_rounded,
        title: reason,
        description: '媒体链接或会话已失效，请返回局域网同步重新连接。',
        action: FilledButton(
          onPressed: () {
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(AppDestination.sync.path);
            }
          },
          child: const Text('返回局域网同步'),
        ),
      ),
    );
  }
}

/// 取路径最后一个段作为文件名。
String _fileNameOf(String normalizedPath) {
  return normalizedPath.split('/').last;
}
