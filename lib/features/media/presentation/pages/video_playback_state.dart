import 'package:video_player/video_player.dart';

/// `copyWith` 的私有哨兵：区分「未传参（保留旧值）」与「显式传 null（清空）」。
///
/// 对 nullable 字段（controller / errorMessage / centerFeedback）使用，
/// 保证能显式清空而不被 `value ?? oldValue` 吞掉。
const Object _unset = Object();

// ── 结构化中央反馈 ────────────────────────────────────────────────

/// 结构化中央反馈的基类。
///
/// 携带实际 delta/target/speed/volume 等数据，`VideoCenterHint` 通过
/// exhaustive switch 读取真实值渲染，不再写死 15 秒 / 3.0 倍速。
sealed class VideoCenterFeedback {
  const VideoCenterFeedback();
}

/// 相对 Seek 反馈：方向与实际秒数、目标位置。
final class VideoRelativeSeekFeedback extends VideoCenterFeedback {
  const VideoRelativeSeekFeedback({required this.delta, required this.target});

  final Duration delta;
  final Duration target;
}

/// Seek 预览反馈：拖动时显示的目标位置。
final class VideoSeekPreviewFeedback extends VideoCenterFeedback {
  const VideoSeekPreviewFeedback(this.target);

  final Duration target;
}

/// 临时倍速反馈：当前有效倍速。
final class VideoTemporarySpeedFeedback extends VideoCenterFeedback {
  const VideoTemporarySpeedFeedback(this.speed);

  final double speed;
}

/// 音量反馈：实际百分比与静音状态。
final class VideoVolumeFeedback extends VideoCenterFeedback {
  const VideoVolumeFeedback({required this.volume, required this.isMuted});

  final double volume;
  final bool isMuted;
}

/// 操作失败反馈：固定安全文案，不暴露平台异常细节。
final class VideoOperationFailureFeedback extends VideoCenterFeedback {
  const VideoOperationFailureFeedback(this.message);

  final String message;
}

// ── 共享播放状态 ──────────────────────────────────────────────────

/// 共享播放 UI 快照的不可变投影。
///
/// Mobile/Desktop 与页面只读取 [VideoPlaybackController.state]，不能修改
/// 本对象。Timer、generation、active lease 等可变生命周期资源只保存在
/// controller 私有字段中，不进入共享状态。
final class VideoPlaybackState {
  const VideoPlaybackState({
    this.controller,
    this.isInitialized = false,
    this.hasError = false,
    this.errorMessage,
    this.controlsVisible = true,
    this.isPlaying = false,
    this.hasEnded = false,
    this.isDragging = false,
    this.dragPositionMs = 0,
    this.bufferedPercent = 0,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.persistentSpeed = 1.0,
    this.effectiveSpeed = 1.0,
    this.volume = 1.0,
    this.lastNonZeroVolume = 1.0,
    this.isMuted = false,
    this.centerFeedback,
  });

  /// 底层播放器控制器：页面据此构建 [VideoPlayer] Widget，
  /// 但不允许绕过共享核心修改其状态。
  final VideoPlayerController? controller;
  final bool isInitialized;
  final bool hasError;
  final String? errorMessage;
  final bool controlsVisible;
  final bool isPlaying;
  final bool hasEnded;
  final bool isDragging;
  final double dragPositionMs;
  final double bufferedPercent;
  final Duration currentPosition;
  final Duration totalDuration;

  /// 顶部倍速菜单选择的常驻倍速。
  final double persistentSpeed;

  /// 底层播放器当前实际速度；临时倍速 lease 期间与 [persistentSpeed] 不同。
  final double effectiveSpeed;
  final double volume;
  final double lastNonZeroVolume;
  final bool isMuted;
  final VideoCenterFeedback? centerFeedback;

  VideoPlaybackState copyWith({
    Object? controller = _unset,
    bool? isInitialized,
    bool? hasError,
    Object? errorMessage = _unset,
    bool? controlsVisible,
    bool? isPlaying,
    bool? hasEnded,
    bool? isDragging,
    double? dragPositionMs,
    double? bufferedPercent,
    Duration? currentPosition,
    Duration? totalDuration,
    double? persistentSpeed,
    double? effectiveSpeed,
    double? volume,
    double? lastNonZeroVolume,
    bool? isMuted,
    Object? centerFeedback = _unset,
  }) {
    return VideoPlaybackState(
      controller: identical(controller, _unset)
          ? this.controller
          : controller as VideoPlayerController?,
      isInitialized: isInitialized ?? this.isInitialized,
      hasError: hasError ?? this.hasError,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      isPlaying: isPlaying ?? this.isPlaying,
      hasEnded: hasEnded ?? this.hasEnded,
      isDragging: isDragging ?? this.isDragging,
      dragPositionMs: dragPositionMs ?? this.dragPositionMs,
      bufferedPercent: bufferedPercent ?? this.bufferedPercent,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      persistentSpeed: persistentSpeed ?? this.persistentSpeed,
      effectiveSpeed: effectiveSpeed ?? this.effectiveSpeed,
      volume: volume ?? this.volume,
      lastNonZeroVolume: lastNonZeroVolume ?? this.lastNonZeroVolume,
      isMuted: isMuted ?? this.isMuted,
      centerFeedback: identical(centerFeedback, _unset)
          ? this.centerFeedback
          : centerFeedback as VideoCenterFeedback?,
    );
  }
}
