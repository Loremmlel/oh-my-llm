import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/notification_bubble_context_ext.dart';
import '../../application/shuffle_playback_controller.dart';
import '../pages/video_player_page.dart';

/// AppBar 随机播放按钮组。
///
/// 根据 [ShufflePlaybackState] 渲染三种形态：
/// - Idle → 🔀 IconButton
/// - Loading → 小型 CircularProgressIndicator
/// - Active → ◀ 上一个 | N/M | 下一个 ▶（边界自适应）
///
/// [currentDirectoryPath] 用于向 controller 传递当前浏览目录。
class ShuffleAppBarActions extends ConsumerWidget {
  final String currentDirectoryPath;

  const ShuffleAppBarActions({
    super.key,
    required this.currentDirectoryPath,
  });

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
      ShufflePlaybackActive() =>
        _buildActiveButtons(context, ref, state, controller),
    };
  }

  Future<void> _onShufflePressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = await controller.startShuffle(currentDirectoryPath);

    if (!context.mounted) return;

    final state = ref.read(shufflePlaybackControllerProvider);
    if (videoUrl != null && state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name, controller);
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
    final videoUrl = controller.playNext();
    if (videoUrl == null) return;
    final state = ref.read(shufflePlaybackControllerProvider);
    if (state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name, controller);
    }
  }

  Future<void> _onPrevPressed(
    BuildContext context,
    WidgetRef ref,
    ShufflePlaybackController controller,
  ) async {
    final videoUrl = controller.playPrevious();
    if (videoUrl == null) return;
    final state = ref.read(shufflePlaybackControllerProvider);
    if (state is ShufflePlaybackActive) {
      _navigateToPlayer(context, videoUrl, state.currentVideo.name, controller);
    }
  }

  Future<void> _navigateToPlayer(
    BuildContext context,
    String videoUrl,
    String fileName,
    ShufflePlaybackController controller,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoUrl: videoUrl,
          fileName: fileName,
        ),
      ),
    );
    if (context.mounted) {
      controller.onPlayerExited();
    }
  }
}
