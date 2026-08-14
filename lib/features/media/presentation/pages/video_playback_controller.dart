import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../application/models/media_resource.dart';
import 'media_video_controller_factory.dart';
import 'video_playback_state.dart';

/// 不可伪造的临时倍速 lease token。
///
/// 构造器私有：只能由 [VideoPlaybackController.beginTemporarySpeed] 创建，
/// 相等性基于实例身份（`identical`），测试不得越过公开 API 构造 stale lease。
final class VideoTemporarySpeedLease {
  const VideoTemporarySpeedLease._(this.id);

  final int id;
}

/// 共享播放核心：底层 [VideoPlayerController] 的唯一 owner。
///
/// 独占播放器生命周期、共享播放状态与跨平台播放命令；Mobile/Desktop 输入
/// controller 只读取 [state] 快照并调用公开命令，不直接触碰底层播放器。
/// 所有 setPlaybackSpeed / setVolume / seekTo / play / pause 调用只存在于
/// 本文件。
class VideoPlaybackController {
  VideoPlaybackController({
    required MediaResource resource,
    required MediaVideoControllerFactory controllerFactory,
    required VoidCallback onStateChanged,
  }) : _resource = resource,
       _controllerFactory = controllerFactory,
       _onStateChanged = onStateChanged;

  final MediaResource _resource;
  final MediaVideoControllerFactory _controllerFactory;
  final VoidCallback _onStateChanged;

  VideoPlaybackState _state = const VideoPlaybackState();
  VideoPlaybackState get state => _state;

  VideoPlayerController? _controller;
  Timer? _hideTimer;
  Timer? _hintTimer;
  VideoTemporarySpeedLease? _activeSpeedLease;
  int _nextLeaseId = 0;

  /// 相对 Seek 手势期间暂存的控制栏显隐（seek 1 秒提示消失后恢复）。
  bool? _seekControlsVisibleBefore;

  /// 控制栏自动隐藏的 hold 计数：hover / 控件焦点 / 弹层打开都会累加，
  /// 全部释放后才恢复三秒自动隐藏。
  int _controlsHoldCount = 0;

  /// 初始化代数：旧 Future 完成时若代数不匹配则丢弃，不覆盖新会话状态。
  int _generation = 0;
  bool _disposed = false;

  // ── 生命周期 ───────────────────────────────────────────────────

  Future<void> initialize() => _replaceController();
  Future<void> retry() => _replaceController();

  Future<void> _replaceController() async {
    final generation = ++_generation;
    _activeSpeedLease = null;
    _hintTimer?.cancel();
    _hideTimer?.cancel();
    _seekControlsVisibleBefore = null;
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;

    try {
      final ctrl = _controllerFactory(_resource);
      _controller = ctrl;
      ctrl.addListener(_onControllerUpdate);

      await ctrl.initialize();
      if (_disposed) return;
      if (generation != _generation) return;
      if (!identical(ctrl, _controller)) return;

      ctrl.setVolume(state.volume);
      ctrl.setPlaybackSpeed(state.persistentSpeed);
      ctrl.play();

      final ended =
          ctrl.value.isCompleted &&
          _isNearEnd(ctrl.value.position, ctrl.value.duration);
      _emit(
        state.copyWith(
          controller: ctrl,
          isInitialized: true,
          hasError: false,
          errorMessage: null,
          hasEnded: ended,
          isPlaying: true,
        ),
      );
      _startHideTimer();
    } catch (e) {
      if (_disposed) return;
      if (generation != _generation) return;
      _controller?.removeListener(_onControllerUpdate);
      _controller?.dispose();
      _controller = null;
      _emit(
        state.copyWith(
          controller: null,
          hasError: true,
          errorMessage: '视频加载失败: $e',
          isInitialized: false,
        ),
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _activeSpeedLease = null;
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;
  }

  /// 应用进入后台/暂停：暂停播放并释放临时倍速，防止暂停后残留 3 倍速。
  void onAppLifecyclePaused() {
    _controller?.pause();
    if (_activeSpeedLease != null) {
      _activeSpeedLease = null;
      _controller?.setPlaybackSpeed(state.persistentSpeed);
      _clearFeedback();
      _emit(state.copyWith(effectiveSpeed: state.persistentSpeed));
    }
  }

  // ── 状态投影 ───────────────────────────────────────────────────

  void _emit(VideoPlaybackState next) {
    _state = next;
    _onStateChanged();
  }

  // ── 播放器状态监听 ─────────────────────────────────────────────

  void _onControllerUpdate() {
    if (_disposed) return;
    final value = _controller?.value;
    if (value == null) return;

    final wasPlaying = state.isPlaying;
    final wasEnded = state.hasEnded;
    final atEnd = _isNearEnd(value.position, value.duration);
    final ended = value.isCompleted && atEnd;

    var next = state.copyWith(
      isPlaying: value.isPlaying,
      currentPosition: value.position,
      totalDuration: value.duration,
      hasEnded: ended,
    );

    final buffered = value.buffered;
    if (buffered.isNotEmpty && value.duration > Duration.zero) {
      next = next.copyWith(
        bufferedPercent:
            (buffered.last.end.inMicroseconds / value.duration.inMicroseconds)
                .clamp(0.0, 1.0),
      );
    }

    if (ended && !wasEnded) {
      next = next.copyWith(controlsVisible: true);
      _hideTimer?.cancel();
    }
    if (wasPlaying && !value.isPlaying && !ended) {
      next = next.copyWith(controlsVisible: true);
    }

    _emit(next);

    if (wasPlaying && !value.isPlaying && !ended) {
      _hideTimer?.cancel();
    } else if (!wasPlaying && value.isPlaying) {
      _startHideTimer();
    }
  }

  bool _isNearEnd(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    final threshold = duration < const Duration(milliseconds: 500)
        ? Duration.zero
        : duration - const Duration(milliseconds: 500);
    return position >= threshold;
  }

  // ── 播放控制 ───────────────────────────────────────────────────

  void togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null || !state.isInitialized) return;

    if (state.hasEnded) {
      ctrl.seekTo(Duration.zero);
      ctrl.play();
      _emit(state.copyWith(hasEnded: false, isPlaying: true));
    } else if (state.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    resetHideTimer();
  }

  void setPersistentSpeed(double speed) {
    _emit(
      state.copyWith(
        persistentSpeed: speed,
        effectiveSpeed: _activeSpeedLease == null
            ? speed
            : state.effectiveSpeed,
      ),
    );
    // 临时倍速期间只更新常驻值，底层速度保持临时值；lease 结束后再恢复。
    if (_activeSpeedLease == null) {
      _controller?.setPlaybackSpeed(speed);
    }
    resetHideTimer();
  }

  void setVolume(double volume) {
    final next = volume.clamp(0.0, 1.0);
    _controller?.setVolume(next);
    _emit(state.copyWith(volume: next));
  }

  // ── 临时倍速 lease ─────────────────────────────────────────────

  VideoTemporarySpeedLease? beginTemporarySpeed(double speed) {
    if (!state.isInitialized || !state.isPlaying || state.hasEnded) return null;
    if (_activeSpeedLease != null) return null;
    final lease = VideoTemporarySpeedLease._(++_nextLeaseId);
    _activeSpeedLease = lease;
    _emit(state.copyWith(effectiveSpeed: speed));
    _controller?.setPlaybackSpeed(speed);
    _showFeedback(VideoTemporarySpeedFeedback(speed), autoHide: false);
    return lease;
  }

  void endTemporarySpeed(VideoTemporarySpeedLease lease) {
    if (!identical(_activeSpeedLease, lease)) return;
    _activeSpeedLease = null;
    _emit(state.copyWith(effectiveSpeed: state.persistentSpeed));
    _controller?.setPlaybackSpeed(state.persistentSpeed);
    _clearFeedback();
  }

  // ── Seek ───────────────────────────────────────────────────────

  void seekRelative(Duration offset) {
    final ctrl = _controller;
    if (ctrl == null || !state.isInitialized || state.hasError) return;

    final target = state.currentPosition + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > state.totalDuration ? state.totalDuration : target);
    ctrl.seekTo(clamped);

    _beginSeekGesture();
    _showFeedback(
      VideoRelativeSeekFeedback(delta: offset, target: clamped),
      onHide: _endSeekGesture,
    );
  }

  double fractionToMs(double fraction) {
    return (state.totalDuration.inMilliseconds * fraction).toDouble().clamp(
      0,
      state.totalDuration.inMilliseconds.toDouble(),
    );
  }

  void onSeekStart(double fraction) {
    if (state.isDragging) return;
    _hideTimer?.cancel();
    final targetMs = fractionToMs(fraction);
    _emit(
      state.copyWith(
        dragPositionMs: targetMs,
        isDragging: true,
        centerFeedback: VideoSeekPreviewFeedback(
          Duration(milliseconds: targetMs.round()),
        ),
      ),
    );
  }

  void onSeekUpdate(double fraction) {
    final targetMs = fractionToMs(fraction);
    _emit(
      state.copyWith(
        dragPositionMs: targetMs,
        centerFeedback: VideoSeekPreviewFeedback(
          Duration(milliseconds: targetMs.round()),
        ),
      ),
    );
  }

  void onSeekEnd() {
    _controller?.seekTo(Duration(milliseconds: state.dragPositionMs.round()));
    _clearFeedback();
    _emit(state.copyWith(isDragging: false));
    resetHideTimer();
  }

  void onSeekCancel() {
    _clearFeedback();
    _emit(state.copyWith(isDragging: false));
    resetHideTimer();
  }

  // ── 控制栏显隐 ─────────────────────────────────────────────────

  void toggleControls() {
    _emit(state.copyWith(controlsVisible: !state.controlsVisible));
    resetHideTimer();
  }

  void showControls() {
    if (!state.controlsVisible) {
      _emit(state.copyWith(controlsVisible: true));
    }
    resetHideTimer();
  }

  void holdControlsVisible() {
    _controlsHoldCount++;
    _hideTimer?.cancel();
  }

  void releaseControlsHold() {
    if (_controlsHoldCount > 0) _controlsHoldCount--;
    if (_controlsHoldCount == 0) resetHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_controlsHoldCount > 0) return;
    if (state.isPlaying && !state.hasEnded) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (_disposed) return;
        _emit(state.copyWith(controlsVisible: false));
      });
    }
  }

  void resetHideTimer() {
    _hideTimer?.cancel();
    if (state.controlsVisible) {
      _startHideTimer();
    }
  }

  // ── 结构化中央反馈 ─────────────────────────────────────────────

  void _showFeedback(
    VideoCenterFeedback feedback, {
    bool autoHide = true,
    VoidCallback? onHide,
  }) {
    _hintTimer?.cancel();
    _emit(state.copyWith(centerFeedback: feedback));
    if (autoHide) {
      _hintTimer = Timer(const Duration(seconds: 1), () {
        if (_disposed) return;
        _emit(state.copyWith(centerFeedback: null));
        onHide?.call();
      });
    }
  }

  void _clearFeedback() {
    _hintTimer?.cancel();
    _emit(state.copyWith(centerFeedback: null));
  }

  // ── 相对 Seek 手势期间控制栏暂存 ──────────────────────────────

  void _beginSeekGesture() {
    if (_seekControlsVisibleBefore != null) return;
    _seekControlsVisibleBefore = state.controlsVisible;
    _hideTimer?.cancel();
    _emit(state.copyWith(controlsVisible: false));
  }

  void _endSeekGesture() {
    final before = _seekControlsVisibleBefore;
    _seekControlsVisibleBefore = null;
    if (before == null) return;
    final target = state.hasEnded ? true : before;
    if (target != state.controlsVisible) {
      _emit(state.copyWith(controlsVisible: target));
    }
    resetHideTimer();
  }
}
