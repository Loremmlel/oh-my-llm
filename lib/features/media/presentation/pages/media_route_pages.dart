import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';

import '../../application/media_browser_controller.dart';
import '../../application/media_library_session_controller.dart';
import '../../application/media_resource_provider.dart';
import '../../application/models/media_library_failure.dart';
import '../../application/models/media_resource_request.dart';
import '../../domain/media_file_classification.dart';
import '../../utils/path_utils.dart';
import 'image_viewer_page.dart';
import 'media_video_controller_factory.dart';
import 'video_player_page.dart';
import 'video_player_platform_bindings.dart';

/// 图片查看的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，结合当前活动媒体会话重建
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

    final session = ref.watch(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      return const MediaRouteRecoveryPage(
        routeTitle: '图片查看',
        reason: '媒体会话已失效',
      );
    }

    final imageRequests = [
      for (final item in ref.watch(mediaBrowserControllerProvider).items)
        if (isImageFile(item.name))
          MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: item.relativePath,
          ),
    ];
    final targetIndex = imageRequests.indexWhere(
      (request) => request.relativePath == normalized,
    );

    if (targetIndex >= 0) {
      // 目标在当前目录图片列表中：按当前 items 顺序恢复画廊。
      return ImageViewerPage(
        imageRequests: imageRequests,
        initialIndex: targetIndex,
      );
    }

    // 目标不在当前列表（direct link/rebuild 时列表未恢复）：单图查看，
    // 资源已删除时由 leaf page 的 broken-image 状态呈现，仍可返回。
    return ImageViewerPage(
      imageRequests: [
        MediaAssetRequest(kind: MediaAssetKind.image, relativePath: normalized),
      ],
    );
  }
}

/// 视频播放的 GoRouter 子路由适配页。
///
/// 从 URL query 接收媒体相对路径，经 [mediaResourceProvider] 懒解析
/// 后重建 [VideoPlayerPage]；[bindingsFactory] 由 app composition 注入的
/// 页面级平台 bindings factory，只在资源解析成功、真正创建播放器时传入
/// 页面（恢复页不创建 bindings）；[controllerFactory] 仅作测试注入的播放器
/// 平台替换，不进入 route state。
class MediaVideoRoutePage extends ConsumerWidget {
  const MediaVideoRoutePage({
    required this.relativePath,
    required this.bindingsFactory,
    this.controllerFactory,
    super.key,
  });

  final String? relativePath;
  final VideoPlayerPlatformBindingsFactory bindingsFactory;
  final MediaVideoControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = normalizeMediaRoutePath(relativePath);
    if (normalized == null || !isVideoFile(_fileNameOf(normalized))) {
      return const MediaRouteRecoveryPage(routeTitle: '视频播放', reason: '媒体链接无效');
    }

    // 与图片路由一致：会话未激活直接走恢复页，不依赖 provider 的失败语义
    final session = ref.watch(mediaLibrarySessionProvider);
    if (session is! MediaLibrarySessionActive) {
      return const MediaRouteRecoveryPage(
        routeTitle: '视频播放',
        reason: '媒体会话已失效',
      );
    }

    final request = MediaAssetRequest(
      kind: MediaAssetKind.video,
      relativePath: normalized,
    );
    final resource = ref.watch(mediaResourceProvider(request));
    // Riverpod 3 的 FutureProvider 失败时状态是「带错误附着的 loading」，
    // 必须先按 hasError 判定，否则错误会被当成加载中
    if (resource.hasError) {
      return MediaRouteRecoveryPage(
        routeTitle: '视频播放',
        reason: _safeReason(resource.error!),
      );
    }
    final value = switch (resource) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (value == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return VideoPlayerPage(
      resource: value,
      fileName: _fileNameOf(normalized),
      controllerFactory: controllerFactory ?? createMediaVideoController,
      platformBindingsFactory: bindingsFactory,
    );
  }

  /// 从资源解析失败中提取安全原因：类型化失败用其消息，未知异常用固定文案。
  static String _safeReason(Object error) {
    if (error is MediaLibraryFailure) return error.message;
    return '媒体资源不可用';
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
        description: '媒体会话已失效，请返回同步页重新打开媒体浏览器。',
        action: FilledButton(
          onPressed: () {
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(AppDestination.sync.path);
            }
          },
          child: const Text('返回同步页'),
        ),
      ),
    );
  }
}

/// 取路径最后一个段作为文件名。
String _fileNameOf(String normalizedPath) {
  return normalizedPath.split('/').last;
}
