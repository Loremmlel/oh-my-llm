import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../widgets/video_player_controls.dart';
import 'video_player_state.dart';

/// 视频播放器手势与播放控制逻辑。
///
/// 封装所有非 UI 逻辑：播放器初始化/销毁、手势响应、控制栏计时器。
/// 通过 [onStateChanged] 回调通知外部重建 UI。
class VideoPlayerGestureController {
  final state = VideoPlayerUiState();

  VoidCallback? onStateChanged;
  VoidCallback? onBackPressed;

  bool _mounted = false;

  void setMounted(bool value) => _mounted = value;

  VideoPlayerController? get controller => state.controller;

  // ── 生命周期 ───────────────────────────────────────────────────

  Future<void> initPlayer(
    Uri uri,
    VideoPlayerController Function(Uri) factory,
  ) async {
    state.controller?.removeListener(_onControllerUpdate);
    state.controller?.dispose();

    state.controller = null;
    state.hasError = false;
    state.errorMessage = null;
    state.bufferedPercent = 0.0;
    state.currentPosition = Duration.zero;
    state.totalDuration = Duration.zero;

    try {
      final ctrl = factory(uri);
      state.controller = ctrl;
      ctrl.addListener(_onControllerUpdate);

      await ctrl.initialize();
      if (!_mounted) return;
      if (ctrl != state.controller) return;

      ctrl.setVolume(state.currentVolume);
      ctrl.setPlaybackSpeed(state.currentSpeed);
      ctrl.play();

      final ended = ctrl.value.isCompleted &&
          _isNearEnd(ctrl.value.position, ctrl.value.duration);
      state.isInitialized = true;
      state.hasError = false;
      state.errorMessage = null;
      state.hasEnded = ended;
      state.isPlaying = true;
      state.isLongPressing = false;
      state.isHorizontalDragging = false;
      onStateChanged?.call();
      _startHideTimer();
    } catch (e) {
      if (!_mounted) return;
      state.hasError = true;
      state.errorMessage = '视频加载失败: $e';
      state.isInitialized = false;
      onStateChanged?.call();
    }
  }

  void dispose() {
    state.hideTimer?.cancel();
    state.hintTimer?.cancel();

    state.controller?.removeListener(_onControllerUpdate);
    if (state.isLongPressing && state.controller != null) {
      state.controller!.setPlaybackSpeed(state.preLongPressSpeed);
    }
    state.controller?.dispose();
    state.controller = null;
    _mounted = false;
  }

  void onAppLifecyclePaused() {
    state.controller?.pause();
  }

  // ── 播放器状态监听 ─────────────────────────────────────────────

  void _onControllerUpdate() {
    if (!_mounted) return;
    final value = state.controller?.value;
    if (value == null) return;

    final wasPlaying = state.isPlaying;

    state.isPlaying = value.isPlaying;
    state.currentPosition = value.position;
    state.totalDuration = value.duration;

    final buffered = value.buffered;
    if (buffered.isNotEmpty && value.duration > Duration.zero) {
      state.bufferedPercent = (buffered.last.end.inMicroseconds /
              value.duration.inMicroseconds)
          .clamp(0.0, 1.0);
    }

    final atEnd = _isNearEnd(value.position, value.duration);
    if (value.isCompleted && !state.hasEnded && atEnd) {
      state.hasEnded = true;
      state.controlsVisible = true;
      state.hideTimer?.cancel();
    }

    if (wasPlaying && !value.isPlaying && !state.hasEnded) {
      state.controlsVisible = true;
    }

    onStateChanged?.call();

    if (wasPlaying && !state.isPlaying && !state.hasEnded) {
      state.hideTimer?.cancel();
    } else if (!wasPlaying && state.isPlaying) {
      _startHideTimer();
    }
  }

  // ── 播放控制 ───────────────────────────────────────────────────

  void togglePlayPause() {
    final ctrl = state.controller;
    if (ctrl == null || !state.isInitialized) return;

    if (state.hasEnded) {
      ctrl.seekTo(Duration.zero);
      ctrl.play();
      state.hasEnded = false;
      state.isPlaying = true;
    } else if (state.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    resetHideTimer();
    onStateChanged?.call();
  }

  void changeSpeed(double speed) {
    state.controller?.setPlaybackSpeed(speed);
    state.currentSpeed = speed;
    resetHideTimer();
    onStateChanged?.call();
  }

  void setVolume(double vol) {
    state.controller?.setVolume(vol);
    state.currentVolume = vol;
    onStateChanged?.call();
  }

  // ── 进度条 Seek ────────────────────────────────────────────────

  double fractionToMs(double fraction) {
    return (state.totalDuration.inMilliseconds * fraction)
        .toDouble()
        .clamp(0, state.totalDuration.inMilliseconds.toDouble());
  }

  void onSeekStart(double fraction) {
    if (state.isHorizontalDragging) return;
    state.hideTimer?.cancel();
    state.dragPositionMs = fractionToMs(fraction);
    state.isDragging = true;
    onStateChanged?.call();
  }

  void onSeekUpdate(double fraction) {
    state.dragPositionMs = fractionToMs(fraction);
    onStateChanged?.call();
  }

  void onSeekEnd() {
    state.controller?.seekTo(
      Duration(milliseconds: state.dragPositionMs.round()),
    );
    state.isDragging = false;
    resetHideTimer();
    onStateChanged?.call();
  }

  // ── 控制栏显隐 ─────────────────────────────────────────────────

  void handleTap() {
    if (!_mounted) return;
    state.controlsVisible = !state.controlsVisible;
    resetHideTimer();
    onStateChanged?.call();
  }

  void _startHideTimer() {
    state.hideTimer?.cancel();
    if (state.isLongPressing || state.isHorizontalDragging) return;
    if (state.isPlaying && !state.hasEnded) {
      state.hideTimer = Timer(const Duration(seconds: 3), () {
        if (!_mounted) return;
        state.controlsVisible = false;
        onStateChanged?.call();
      });
    }
  }

  void resetHideTimer() {
    state.hideTimer?.cancel();
    if (state.controlsVisible) {
      _startHideTimer();
    }
  }

  // ── 播放结束检测 ───────────────────────────────────────────────

  bool _isNearEnd(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    final threshold = duration < const Duration(milliseconds: 500)
        ? Duration.zero
        : duration - const Duration(milliseconds: 500);
    return position >= threshold;
  }

  // ── 手势辅助 ─────────────────────────────────────────────────

  void beginGesture() {
    if (state.controlsVisibleBeforeGesture != null) return;
    state.controlsVisibleBeforeGesture = state.controlsVisible;
    state.controlsVisible = false;
    state.hideTimer?.cancel();
    onStateChanged?.call();
  }

  void endGesture() {
    if (state.controlsVisibleBeforeGesture != null) {
      state.controlsVisible =
          state.hasEnded ? true : state.controlsVisibleBeforeGesture!;
      state.controlsVisibleBeforeGesture = null;
      resetHideTimer();
      onStateChanged?.call();
    }
  }

  void showCenterHint(CenterHintType type, {VoidCallback? onHintDismissed}) {
    state.hintTimer?.cancel();
    state.centerHint = type;
    state.hintTimer = Timer(const Duration(seconds: 1), () {
      if (!_mounted) return;
      state.centerHint = CenterHintType.none;
      onHintDismissed?.call();
      onStateChanged?.call();
    });
    onStateChanged?.call();
  }

  void hideCenterHint() {
    state.hintTimer?.cancel();
    if (_mounted) {
      state.centerHint = CenterHintType.none;
      onStateChanged?.call();
    }
  }

  // ── 双击 ─────────────────────────────────────────────────────

  void handleDoubleTapDown(TapDownDetails details) {
    state.lastTapPositionDx = details.globalPosition.dx;
  }

  void handleDoubleTap() {
    final ctrl = state.controller;
    if (ctrl == null || !state.isInitialized || state.hasError) return;

    final isLeftHalf =
        (state.lastTapPositionDx ?? 0) < state.cachedScreenWidth / 2;
    final targetPosition = isLeftHalf
        ? state.currentPosition - const Duration(seconds: 15)
        : state.currentPosition + const Duration(seconds: 15);

    final clamped = targetPosition < Duration.zero
        ? Duration.zero
        : (targetPosition > state.totalDuration
            ? state.totalDuration
            : targetPosition);
    ctrl.seekTo(clamped);

    beginGesture();
    showCenterHint(
      isLeftHalf ? CenterHintType.rewind : CenterHintType.fastForward,
      onHintDismissed: endGesture,
    );
  }

  // ── 长按 ─────────────────────────────────────────────────────

  void handleLongPressStart(LongPressStartDetails details) {
    final ctrl = state.controller;
    if (ctrl == null || !state.isInitialized || state.hasError) return;
    if (!state.isPlaying || state.hasEnded) return;

    state.preLongPressSpeed = state.currentSpeed;
    state.isLongPressing = true;
    ctrl.setPlaybackSpeed(3.0);
    beginGesture();
    showCenterHint(CenterHintType.speed);
  }

  void _endLongPress() {
    if (!_mounted) return;
    if (!state.isLongPressing) return;
    state.isLongPressing = false;
    state.controller?.setPlaybackSpeed(state.preLongPressSpeed);
    hideCenterHint();
    endGesture();
  }

  void handleLongPressEnd(LongPressEndDetails details) {
    _endLongPress();
  }

  void handleLongPressCancel() {
    _endLongPress();
  }

  // ── 水平拖动 Seek ────────────────────────────────────────────

  void handleHorizontalDragStart(DragStartDetails details) {
    final ctrl = state.controller;
    if (ctrl == null || !state.isInitialized || state.hasError) return;
    if (state.isDragging) return;
    if (state.totalDuration <= Duration.zero) return;

    state.dragStartPosition = state.currentPosition;
    state.seekPreviewPosition = state.currentPosition;
    state.dragStartDx = details.globalPosition.dx;
    state.isHorizontalDragging = true;
    beginGesture();
  }

  void handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_mounted) return;
    if (!state.isHorizontalDragging) return;
    if (state.totalDuration.inMilliseconds == 0) return;

    final deltaPixels = details.globalPosition.dx - state.dragStartDx;
    final fraction = deltaPixels / state.cachedScreenWidth;
    final offsetMs =
        (fraction * state.totalDuration.inMilliseconds).round();
    final targetMs = (state.dragStartPosition.inMilliseconds + offsetMs)
        .clamp(0, state.totalDuration.inMilliseconds);

    state.seekPreviewPosition = Duration(milliseconds: targetMs);
    state.hintTimer?.cancel();
    if (state.centerHint != CenterHintType.seek) {
      state.centerHint = CenterHintType.seek;
    }
    onStateChanged?.call();
  }

  void handleHorizontalDragEnd(DragEndDetails details) {
    if (!_mounted) return;
    if (!state.isHorizontalDragging) return;
    state.isHorizontalDragging = false;
    state.controller?.seekTo(state.seekPreviewPosition);
    hideCenterHint();
    endGesture();
  }

  void onBack() {
    onBackPressed?.call();
  }
}
