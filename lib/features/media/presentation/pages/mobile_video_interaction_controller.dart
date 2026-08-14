import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'video_playback_controller.dart';

/// 移动端（Android）触摸与外接键盘输入状态机。
///
/// 只把触摸/按键事件翻译为共享核心的公开命令；不直接调用底层播放器，不
/// 保存播放器位置、音量、倍速等事实值，只读取 [VideoPlaybackController.state]
/// 快照。双击落点、屏幕宽度、长按 lease、横拖起点与手势前控制栏显隐等
/// 输入瞬态保存在本 controller 私有字段，不进入共享状态。
class MobileVideoInteractionController {
  MobileVideoInteractionController({required VideoPlaybackController playback})
    : _playback = playback;

  final VideoPlaybackController _playback;

  // ── 输入私有状态 ───────────────────────────────────────────────
  double _lastTapPositionDx = 0;
  double _cachedScreenWidth = 0;
  VideoTemporarySpeedLease? _longPressLease;
  double _dragStartDx = 0;
  Duration _dragStartPosition = Duration.zero;
  bool _dragging = false;
  bool _gesturing = false;
  bool? _controlsVisibleBeforeGesture;
  bool _disposed = false;

  /// 页面 build 时传入当前屏幕宽度，供双击左右半区与横拖像素换算使用。
  void updateScreenWidth(double width) {
    _cachedScreenWidth = width;
  }

  // ── 单击 / 双击 ────────────────────────────────────────────────

  void handleTap() {
    if (_disposed) return;
    _playback.toggleControls();
  }

  void handleDoubleTapDown(TapDownDetails details) {
    _lastTapPositionDx = details.globalPosition.dx;
  }

  void handleDoubleTap() {
    if (!_playback.state.isInitialized || _playback.state.hasError) return;
    final isLeftHalf = _lastTapPositionDx < _cachedScreenWidth / 2;
    _playback.seekRelative(Duration(seconds: isLeftHalf ? -15 : 15));
  }

  // ── 长按临时倍速 ───────────────────────────────────────────────

  void handleLongPressStart(LongPressStartDetails details) {
    if (!_playback.state.isInitialized || _playback.state.hasError) return;
    if (!_playback.state.isPlaying || _playback.state.hasEnded) return;
    _longPressLease = _playback.beginTemporarySpeed(3.0);
    _beginGesture();
  }

  void handleLongPressEnd(LongPressEndDetails details) => _endLongPress();

  void handleLongPressCancel() => _endLongPress();

  void _endLongPress() {
    if (_disposed) return;
    final lease = _longPressLease;
    _longPressLease = null;
    if (lease != null) {
      _playback.endTemporarySpeed(lease);
    }
    _endGesture();
  }

  // ── 水平拖动 Seek ─────────────────────────────────────────────

  void handleHorizontalDragStart(DragStartDetails details) {
    if (!_playback.state.isInitialized || _playback.state.hasError) return;
    if (_dragging || _playback.state.isDragging) return;
    if (_playback.state.totalDuration <= Duration.zero) return;
    _dragStartDx = details.globalPosition.dx;
    _dragStartPosition = _playback.state.currentPosition;
    _dragging = true;
    _beginGesture();
  }

  void handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_disposed || !_dragging) return;
    final totalMs = _playback.state.totalDuration.inMilliseconds;
    if (totalMs == 0) return;
    final deltaPixels = details.globalPosition.dx - _dragStartDx;
    final fraction = deltaPixels / _cachedScreenWidth;
    final offsetMs = (fraction * totalMs).round();
    final targetMs = (_dragStartPosition.inMilliseconds + offsetMs).clamp(
      0,
      totalMs,
    );
    _playback.onSeekUpdate(targetMs / totalMs);
  }

  void handleHorizontalDragEnd(DragEndDetails details) {
    _finishHorizontalDrag(commit: true);
  }

  void handleHorizontalDragCancel() {
    _finishHorizontalDrag(commit: false);
  }

  /// 横拖唯一收口：提交 seek（commit=true）或回滚预览（commit=false）。
  ///
  /// 系统取消（Android 返回手势抢占触摸）经 [CancelAwareHorizontalDragRecognizer]
  /// 转译为 onCancel 先到达这里：拖动状态复位、提示隐藏、控制栏恢复；
  /// 随后框架对已接受拖动的 cancel 仍按 onEnd 派发，但会被 [_dragging]
  /// 守卫拦截，不会二次提交 seek。
  void _finishHorizontalDrag({required bool commit}) {
    if (_disposed || !_dragging) return;
    _dragging = false;
    if (commit) {
      _playback.onSeekEnd();
    } else {
      _playback.onSeekCancel();
    }
    _endGesture();
  }

  // ── 外接键盘（Android 可访问性路径）────────────────────────────

  /// 播放表面按键：只响应 KeyDown 且仅在表面拥有主焦点时由页面调用；
  /// Escape 的页面关闭由页面处理，不属于本控制器。
  KeyEventResult handleSurfaceKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
        _playback.toggleControls();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _playback.togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _playback.seekRelative(const Duration(seconds: -15));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _playback.seekRelative(const Duration(seconds: 15));
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── 手势期间控制栏暂存与恢复 ──────────────────────────────────

  void _beginGesture() {
    if (_gesturing) return;
    _gesturing = true;
    _controlsVisibleBeforeGesture = _playback.state.controlsVisible;
    if (_controlsVisibleBeforeGesture!) {
      _playback.toggleControls();
    }
  }

  void _endGesture() {
    if (!_gesturing) return;
    _gesturing = false;
    final before = _controlsVisibleBeforeGesture;
    _controlsVisibleBeforeGesture = null;
    if (before == null) return;
    final shouldShow = _playback.state.hasEnded || before;
    if (shouldShow && !_playback.state.controlsVisible) {
      _playback.showControls();
    }
  }

  void dispose() {
    _disposed = true;
    final lease = _longPressLease;
    _longPressLease = null;
    if (lease != null) {
      _playback.endTemporarySpeed(lease);
    }
    if (_dragging) {
      _playback.onSeekCancel();
      _dragging = false;
    }
    _gesturing = false;
    _controlsVisibleBeforeGesture = null;
  }
}

// ── 取消感知的横向拖动识别器 ──────────────────────────────────

/// 感知系统取消的横向拖动识别器。
///
/// Android 系统手势（如返回手势）抢占触摸时以 [PointerCancelEvent] 取消指针；
/// 框架对「已接受的拖动」按 onEnd 派发而非 onCancel，播放器会照常提交
/// seek，与系统返回手势发生冲突。此识别器把「拖动已接受后收到
/// pointer cancel」转译为 onCancel：控制器先回滚（拖动状态复位、隐藏
/// 提示、恢复控制栏），随后框架派发的 onEnd 被控制器守卫拦截，不提交
/// seek。
class CancelAwareHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  CancelAwareHorizontalDragRecognizer({super.debugOwner});

  bool _pointerWasCancelled = false;
  bool _dragAccepted = false;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) {
      _pointerWasCancelled = true;
    }
    super.handleEvent(event);
  }

  @override
  void acceptGesture(int pointer) {
    _dragAccepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // 无条件复位两个标志：接受前的 cancel 也会走到这里，若只在转译分支
    // 内复位，残留的 _pointerWasCancelled 会让下一次正常完成的拖动
    // 误判为取消（不提交 seek）。
    final cancelled = _pointerWasCancelled && _dragAccepted;
    _pointerWasCancelled = false;
    _dragAccepted = false;
    if (cancelled) {
      onCancel?.call();
    }
    super.didStopTrackingLastPointer(pointer);
  }
}
