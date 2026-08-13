import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';
import '../../application/shuffle_playback_controller.dart';

/// AppBar 随机播放按钮组。
///
/// 根据 [ShufflePlaybackState] 渲染三种形态：
/// - Idle → 🔀 IconButton
/// - Loading → 小型 CircularProgressIndicator
/// - Active → ◀ 上一个 | N/M | 下一个 ▶（边界自适应）
///
/// [currentDirectoryPath] 用于向 controller 传递当前浏览目录。
/// start/next/previous 的返回值是相对路径，直接交给媒体播放路由；
/// 本组件不调用任何资源解析器。
class ShuffleAppBarActions extends ConsumerWidget {
  final String currentDirectoryPath;

  const ShuffleAppBarActions({super.key, required this.currentDirectoryPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shufflePlaybackControllerProvider);
    final controller = ref.read(shufflePlaybackControllerProvider.notifier);

    return switch (state) {
      ShufflePlaybackIdle() => IconButton(
        icon: const Icon(Icons.shuffle),
        tooltip: '随机播放',
        onPressed: () => _onShufflePressed(context, ref, controller),
      ),
      ShufflePlaybackLoading() => const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      ShufflePlaybackActive() => _buildActiveButtons(
        context,
        ref,
        state,
        controller,
      ),
    };
  }

  Future<void> _onShufflePressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final path = await controller.startShuffle(currentDirectoryPath);

    if (!context.mounted) return;

    final state = ref.read(shufflePlaybackControllerProvider);
    if (path != null && state is ShufflePlaybackActive) {
      _navigateToPlayer(context, path, controller);
    } else {
      context.showWarningBubble('当前目录下未找到视频文件');
    }
  }

  Widget _buildActiveButtons(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackActive state,
    ShufflePlaybackController controller,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!state.isFirst)
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: '上一个',
            onPressed: () => _onPrevPressed(context, ref, controller),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${state.displayNumber}/${state.totalCount}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!state.isLast)
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: '下一个',
            onPressed: () => _onNextPressed(context, ref, controller),
          ),
      ],
    );
  }

  Future<void> _onNextPressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final path = controller.playNext();
    if (path == null) return;
    _navigateToPlayer(context, path, controller);
  }

  Future<void> _onPrevPressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final path = controller.playPrevious();
    if (path == null) return;
    _navigateToPlayer(context, path, controller);
  }

  Future<void> _navigateToPlayer(
    BuildContext context,
    String relativePath,
    ShufflePlaybackController controller,
  ) async {
    await context.pushNamed(
      AppRouteName.mediaVideo,
      queryParameters: {AppRouteParameter.mediaPath: relativePath},
    );
    if (context.mounted) {
      controller.onPlayerExited();
    }
  }
}
