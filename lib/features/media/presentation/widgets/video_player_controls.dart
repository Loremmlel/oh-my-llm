import 'package:flutter/material.dart';

// ── 时间格式化 ──────────────────────────────────────────────────────

/// 将 Duration 格式化为显示字符串。
///
/// 视频 ≥1 小时显示 `h:mm:ss`，否则显示 `mm:ss`。
String formatVideoDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ── 音量图标 ────────────────────────────────────────────────────────

/// 根据音量值返回对应图标。
IconData volumeIconData(double volume) {
  if (volume <= 0.001) return Icons.volume_off;
  if (volume < 0.5) return Icons.volume_down;
  return Icons.volume_up;
}

// ── 顶部控制栏 ──────────────────────────────────────────────────────

/// 视频播放器顶部控制栏。
///
/// 包含返回按钮、文件名、倍速选择器和音量按钮。
class VideoTopBar extends StatelessWidget {
  final String fileName;
  final double playbackSpeed;
  final double volume;
  final VoidCallback onBack;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onVolumeChanged;
  /// 弹窗打开时调用（用于取消自动隐藏计时器）
  final VoidCallback? onInteractionStarted;
  /// 弹窗关闭时调用（用于重启自动隐藏计时器）
  final VoidCallback? onInteractionEnded;

  const VideoTopBar({
    super.key,
    required this.fileName,
    required this.playbackSpeed,
    required this.volume,
    required this.onBack,
    required this.onSpeedChanged,
    required this.onVolumeChanged,
    this.onInteractionStarted,
    this.onInteractionEnded,
  });

  // 倍速选项列表
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── 返回按钮 ──
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: onBack,
        ),
        const SizedBox(width: 8),
        // ── 文件名 ──
        Expanded(
          child: Text(
            fileName,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 8),
        // ── 倍速选择器 ──
        PopupMenuButton<double>(
          onOpened: onInteractionStarted,
          onCanceled: onInteractionEnded,
          onSelected: (speed) {
            onSpeedChanged(speed);
            onInteractionEnded?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              '${playbackSpeed}x',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          itemBuilder: (context) => [
            for (final speed in _speeds)
              PopupMenuItem<double>(
                value: speed,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${speed}x',
                      style: const TextStyle(fontSize: 15),
                    ),
                    if ((speed - playbackSpeed).abs() < 0.001)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),
          ],
        ),
        // ── 音量按钮 ──
        IconButton(
          icon: Icon(volumeIconData(volume), color: Colors.white),
          onPressed: () => _showVolumeDialog(context),
        ),
      ],
    );
  }

  /// 显示音量调节弹窗。
  ///
  /// 弹窗内容使用 StatefulWidget 管理自身音量状态，
  /// 确保 Slider 拖拽过程中 UI 实时更新，不会在松手后回弹。
  void _showVolumeDialog(BuildContext context) {
    onInteractionStarted?.call();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _VolumeDialogContent(
        initialVolume: volume,
        onVolumeChanged: onVolumeChanged,
      ),
    ).then((_) {
      onInteractionEnded?.call();
    });
  }
}

// ── 音量弹窗内容（StatefulWidget，解决 Slider 回弹问题）────────────

/// 音量弹窗的 StatefulWidget 内容。
///
/// 自身维护 [_volume] 状态，拖拽时通过 [onVolumeChanged] 同步到播放器，
/// 同时本地 setState 确保 Slider UI 实时跟随手指位置。
class _VolumeDialogContent extends StatefulWidget {
  final double initialVolume;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeDialogContent({
    required this.initialVolume,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeDialogContent> createState() => _VolumeDialogContentState();
}

class _VolumeDialogContentState extends State<_VolumeDialogContent> {
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('音量 ${(_volume * 100).round()}%'),
      content: SizedBox(
        height: 200,
        child: RotatedBox(
          quarterTurns: 1,
          child: Slider(
            value: _volume,
            min: 0,
            max: 1,
            divisions: 100,
            label: '${(_volume * 100).round()}%',
            onChanged: (v) {
              setState(() => _volume = v);
              widget.onVolumeChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

// ── 底部控制栏 ──────────────────────────────────────────────────────

/// 视频播放器底部控制栏。
///
/// 包含播放/暂停按钮、可拖动进度条（带缓冲指示）和时间显示。
class VideoBottomBar extends StatelessWidget {
  final bool isPlaying;
  final bool hasEnded;
  final Duration currentPosition;
  final Duration totalDuration;
  final double bufferedPercent;
  final bool isDragging;
  final Duration dragPosition;
  final VoidCallback onPlayPause;
  /// 开始拖动进度条，参数为归一化位置 0.0-1.0
  final ValueChanged<double> onSeekStart;
  /// 拖动进度条中，参数为归一化位置 0.0-1.0
  final ValueChanged<double> onSeekUpdate;
  /// 松手执行 seek
  final VoidCallback onSeekEnd;

  const VideoBottomBar({
    super.key,
    required this.isPlaying,
    required this.hasEnded,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedPercent,
    required this.isDragging,
    required this.dragPosition,
    required this.onPlayPause,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    final hasDuration = totalDuration > Duration.zero;
    final displayPosition = isDragging ? dragPosition : currentPosition;

    // 归一化进度值 (0.0 - 1.0)，无时长时置零
    final totalMs = totalDuration.inMilliseconds.toDouble();
    final normalizedValue = hasDuration
        ? (displayPosition.inMilliseconds.toDouble() / totalMs)
            .clamp(0.0, 1.0)
        : 0.0;

    // 播放/暂停图标：播放结束或暂停时显示播放图标
    final showPlayIcon = hasEnded || (!isPlaying && !isDragging);
    // 缓冲（仅在有时长且未结束时显示）
    final showBuffer = hasDuration && !hasEnded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // ── 播放/暂停按钮 ──
          IconButton(
            icon: Icon(
              showPlayIcon ? Icons.play_arrow : Icons.pause,
              color: Colors.white,
              size: 36,
            ),
            onPressed: onPlayPause,
          ),
          // ── 进度条区域 ──
          // 始终显示 Slider，无时长时处于禁用状态（0% 无法交互）
          Expanded(
            child: SizedBox(
              height: 40, // 给 Slider 足够的触摸高度
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 缓冲进度指示（仅在有时长且未结束时显示）
                  if (showBuffer)
                    Positioned(
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: bufferedPercent.clamp(0.0, 1.0),
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white24,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  // 可拖动进度条（无时长时禁用）
                  SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 4,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: normalizedValue,
                      onChangeStart: hasDuration ? onSeekStart : null,
                      onChanged: hasDuration ? onSeekUpdate : null,
                      onChangeEnd: hasDuration ? (_) => onSeekEnd() : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── 时间显示 ──
          SizedBox(
            width: 96,
            child: Text(
              hasDuration
                  ? '${formatVideoDuration(displayPosition)} / ${formatVideoDuration(totalDuration)}'
                  : '--:--',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 中央提示区域 ────────────────────────────────────────────────────

/// 视频播放器中央提示区域。
///
/// 圆角矩形半透明背景，尺寸仅包裹内容。用于显示暂停/播放结束图标。
/// Phase 6 可扩展为快进/快退/Seek/倍速提示。
class VideoCenterHint extends StatelessWidget {
  /// 是否显示（仅在暂停或播放结束时为 true）
  final bool visible;

  const VideoCenterHint({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // 25% 透明度，符合 PRD 20%-35% 要求
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
      ),
    );
  }
}
