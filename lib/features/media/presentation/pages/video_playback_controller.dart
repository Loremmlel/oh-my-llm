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

      // 初始化从底层 controller value 投影真实音量：不为零时同步记忆音量，
      // 为零时保留默认 100%，不把平台初始音量写死为固定值。
      final projectedVolume = ctrl.value.volume.clamp(0.0, 1.0);
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
          volume: projectedVolume,
          lastNonZeroVolume: projectedVolume > 0.0
              ? projectedVolume
              : state.lastNonZeroVolume,
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
    _clearActiveSpeedLease();
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

    // 进入播放结束或由播放转为暂停：先释放临时倍速 lease，让后续状态投影
    // 基于恢复后的常驻速度，防止 `effectiveSpeed` 残留 3 倍速。
    if ((ended && !wasEnded) || (wasPlaying && !value.isPlaying)) {
      _clearActiveSpeedLease();
    }

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

  /// 设置绝对音量：clamp 到 [0,1] 并清除显式静音。
  ///
  /// Slider 直接设置音量时先解除静音；设为 0 不标记为显式静音，
  /// 也不覆盖最后非零音量（见 [_applyVolume]）。
  void setVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    _applyVolume(next, isMuted: false);
  }

  /// 相对当前音量调整：静音时先以记忆音量解除静音，再应用步进。
  ///
  /// 手动零音量时按上调从 0% 开始（base 取当前音量 0），
  /// 下调继续保持在 0%；未静音时 base 就是当前音量。
  void adjustVolume(double delta) {
    final base = state.isMuted ? state.lastNonZeroVolume : state.volume;
    _applyVolume((base + delta).clamp(0.0, 1.0), isMuted: false);
  }

  /// 切换显式静音：非静音且音量大于零时保存当前音量并把底层音量置零；
  /// 显式静音或手动零音量时恢复最后非零音量。
  void toggleMute() {
    if (state.isMuted || state.volume <= 0.0) {
      _applyVolume(state.lastNonZeroVolume, isMuted: false);
      return;
    }
    _applyVolume(0.0, isMuted: true, rememberedVolume: state.volume);
  }

  /// 音量命令唯一收口：一次 copyWith 写入 volume/mute/lastNonZero 后通知 UI。
  ///
  /// 只有新值与当前底层音量差异超过 0.0001 时才调用底层 setter，避免边界
  /// 无变化时重复写播放器；[rememberedVolume] 优先作为记忆音量，否则大于零
  /// 的新值更新 lastNonZero。每次成功命令都刷新同一个音量反馈节点。
  void _applyVolume(
    double value, {
    required bool isMuted,
    double? rememberedVolume,
  }) {
    final clamped = value.clamp(0.0, 1.0);
    if ((clamped - state.volume).abs() > 0.0001) {
      _controller?.setVolume(clamped);
    }
    final nextLastNonZero =
        rememberedVolume ?? (clamped > 0.0 ? clamped : state.lastNonZeroVolume);
    _emit(
      state.copyWith(
        volume: clamped,
        isMuted: isMuted,
        lastNonZeroVolume: nextLastNonZero,
      ),
    );
    _showFeedback(VideoVolumeFeedback(volume: clamped, isMuted: isMuted));
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
    _clearActiveSpeedLease();
  }

  /// 释放当前激活的临时倍速 lease 并恢复常驻倍速；无激活 lease 时为空操作。
  ///
  /// 播放结束、暂停等播放器驱动的事件会主动释放 lease，防止暂停后残留
  /// 3 倍速；迟到的 KeyUp / 长按结束经 [endTemporarySpeed] 的 `identical`
  /// 守卫走同一路径，重复调用幂等。
  void _clearActiveSpeedLease() {
    if (_activeSpeedLease == null) return;
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

  /// 显示固定安全文案的操作失败反馈，不暴露平台异常细节（如全屏插件错误）。
  void showOperationFailure(String message) {
    _showFeedback(VideoOperationFailureFeedback(message));
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
