import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'video_player_platform_bindings.dart';
import 'video_playback_controller.dart';

/// Windows 桌面键盘与鼠标输入状态机。
///
/// 只把按键 down/repeat/up 序列、鼠标活动、悬停与垂直滚轮翻译为共享核心的公开
/// 命令与全屏窄端口，不读取 BuildContext/FocusNode/Navigator，不保存播放位置、
/// 音量、常驻倍速等事实值。右方向键的短按/长按互斥、400ms 计时器、临时倍速
/// lease、三秒光标静止计时与 50ms 滚轮节流都是本 controller 的私有瞬态，
/// 不进入共享状态。
///
/// 光标显隐是独立于共享控制栏计时器的第二条计时：同一鼠标活动时点调用
/// [VideoPlaybackController.showControls] 让两者同步，但互不持有对方的状态。
///
/// 作用域约定：播放表面主焦点下的 Space/媒体键/Enter/四方向键走
/// [handleSurfaceKey]；视频页面且无更高层弹层时的 M/F/Escape 走 [handlePageKey]；
/// 播放区域内的 pointer signal（滚轮）走 [handlePointerSignal]。
class DesktopVideoInteractionController {
  DesktopVideoInteractionController({
    required VideoPlaybackController playback,
    required VideoFullscreenController fullscreen,
    required Future<void> Function() onRequestClose,
    required VoidCallback onInteractionChanged,
    Timer Function(Duration, VoidCallback) timerFactory = Timer.new,
  }) : _playback = playback,
       _fullscreen = fullscreen,
       _onRequestClose = onRequestClose,
       _onInteractionChanged = onInteractionChanged,
       _timerFactory = timerFactory;

  final VideoPlaybackController _playback;
  final VideoFullscreenController _fullscreen;
  final Future<void> Function() _onRequestClose;
  final VoidCallback _onInteractionChanged;
  final Timer Function(Duration, VoidCallback) _timerFactory;

  // ── 右方向键短按/长按互斥状态 ──────────────────────────────
  bool _rightPressed = false;
  bool _rightClassifiedAsHold = false;
  Timer? _rightHoldTimer;
  VideoTemporarySpeedLease? _rightSpeedLease;
  bool _disposed = false;

  // ── 鼠标活动、控制栏与光标显隐 ──────────────────────────────
  /// 指针当前是否位于任一控制栏内。
  bool _pointerInsideControls = false;

  /// 控制栏内是否有键盘焦点（按钮/Slider，或弹层打开时视作保持）。
  bool _controlsHaveFocus = false;

  /// 音量弹窗 / 倍速菜单等弹层是否打开：与 hover/focus 一起聚合为保持来源。
  bool _controlsPopupOpen = false;

  /// 是否已向共享核心持有控制栏（聚合 hover/focus/弹层的单一 owner）。
  bool _holdsPlaybackControls = false;

  /// 光标可见性投影：Desktop 页面据此选择 MouseRegion 的 cursor。
  bool _isCursorVisible = true;

  /// 三秒静止光标隐藏计时器（与共享核心控制栏计时器分开持有）。
  Timer? _cursorIdleTimer;

  /// 上一次影响保持策略的播放状态值：position tick 等无关变化不重排计时。
  bool _lastPlaybackKeepsCursor = false;

  /// 滚轮 50ms leading-edge 节流：窗口内首个事件立即生效，其余忽略。
  bool _wheelThrottled = false;
  Timer? _wheelThrottleTimer;

  // ── 公开入口 ──────────────────────────────────────────────

  /// 光标当前是否可见；Desktop 页面据此选择 `MouseRegion.cursor`。
  bool get isCursorVisible => _isCursorVisible;

  /// 播放表面按键：Space/媒体播放暂停/Enter/四方向键。
  KeyEventResult handleSurfaceKey(KeyEvent event) {
    if (event is KeyUpEvent) return _handleSurfaceKeyUp(event.logicalKey);
    if (event is KeyRepeatEvent) return _handleSurfaceRepeat(event.logicalKey);
    if (event is KeyDownEvent) return _handleSurfaceKeyDown(event.logicalKey);
    return KeyEventResult.ignored;
  }

  /// 视频页面级按键：只处理 M/F/Escape。
  KeyEventResult handlePageKey(KeyEvent event) {
    if (event is KeyUpEvent) return _handlePageKeyUp(event.logicalKey);
    if (event is KeyRepeatEvent) return _handlePageRepeat(event.logicalKey);
    if (event is KeyDownEvent) return _handlePageKeyDown(event.logicalKey);
    return KeyEventResult.ignored;
  }

  /// 播放表面鼠标活动：显示控件与光标并重启三秒静止计时。
  void onPointerActivity() {
    if (_disposed) return;
    _setCursorVisible(true);
    _playback.showControls();
    _scheduleCursorHide();
  }

  /// 指针进入任一控制栏：暂停光标隐藏并持有共享控制栏。
  void onControlsPointerEnter() {
    if (_disposed) return;
    _pointerInsideControls = true;
    _refreshControlsHoldAndCursor();
  }

  /// 指针离开全部控制栏：按真实 hover/focus/弹层重新计算。
  void onControlsPointerExit() {
    if (_disposed) return;
    _pointerInsideControls = false;
    _refreshControlsHoldAndCursor();
  }

  /// 控制栏内键盘焦点变化（按钮/Slider 聚焦或移出）。
  void onControlsFocusChanged(bool hasFocus) {
    if (_disposed) return;
    _controlsHaveFocus = hasFocus;
    _refreshControlsHoldAndCursor();
  }

  /// 音量弹窗 / 倍速菜单打开：暂停自动隐藏并保持光标可见。
  void onControlsPopupOpened() {
    if (_disposed) return;
    _controlsPopupOpen = true;
    _refreshControlsHoldAndCursor();
  }

  /// 音量弹窗 / 倍速菜单关闭：依据真实 focus/hover 重新计算，不无条件释放。
  void onControlsPopupClosed() {
    if (_disposed) return;
    _controlsPopupOpen = false;
    _refreshControlsHoldAndCursor();
  }

  /// 共享播放状态变化后由页面转发；只在影响保持策略的值变化时重排光标计时，
  /// 避免每个 position tick 都重启三秒。
  void onPlaybackStateChanged() {
    if (_disposed) return;
    final keeps = _playbackKeepsCursorVisible;
    if (keeps == _lastPlaybackKeepsCursor) return;
    _lastPlaybackKeepsCursor = keeps;
    _scheduleCursorHide();
  }

  /// 播放区域内垂直滚轮按 5% 步进调节音量；水平或横向主导事件完全忽略，
  /// 接受的事件受 50ms leading-edge 节流，且同样计作鼠标活动。
  void handlePointerSignal(PointerSignalEvent event) {
    if (_disposed) return;
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta.dx.abs() >= delta.dy.abs()) return;
    if (_wheelThrottled) return;
    _wheelThrottled = true;
    _playback.adjustVolume(delta.dy < 0 ? 0.05 : -0.05);
    _wheelThrottleTimer = _timerFactory(const Duration(milliseconds: 50), () {
      _wheelThrottled = false;
      _wheelThrottleTimer = null;
    });
    onPointerActivity();
  }

  /// 播放表面失去主焦点：取消 pending/hold，不执行短按 Seek。
  void onSurfaceFocusLost() => _cancelRightState();

  /// 窗口失焦：取消 pending/hold、滚轮节流并恢复可见光标，不等待丢失的 KeyUp。
  void onWindowBlur() {
    _cancelRightState();
    _cancelWheelThrottle();
    _cancelCursorVisibility(notify: true);
  }

  /// 播放结束：hold 收口，释放临时倍速，不执行短按 Seek。
  void onPlaybackEnded() => _cancelRightState();

  /// 初始化重试前取消进行中的右方向键、滚轮节流与光标计时。
  void cancelForRetry() {
    _cancelRightState();
    _cancelWheelThrottle();
    _cancelCursorVisibility(notify: true);
  }

  /// 页面销毁：幂等清理，取消全部计时器并恢复可见光标。
  void dispose() {
    _disposed = true;
    _cancelRightState();
    _cancelWheelThrottle();
    _cancelCursorVisibility(notify: false);
  }

  // ── 表面按键 down/repeat/up ───────────────────────────────

  KeyEventResult _handleSurfaceKeyDown(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        _playback.togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _playback.toggleControls();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _playback.seekRelative(const Duration(seconds: -5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _onRightDown();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _playback.adjustVolume(0.05);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _playback.adjustVolume(-0.05);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleSurfaceRepeat(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _playback.adjustVolume(0.05);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _playback.adjustVolume(-0.05);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
      case LogicalKeyboardKey.enter:
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleSurfaceKeyUp(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.arrowRight:
        _onRightUp();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
      case LogicalKeyboardKey.enter:
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── 页面按键 down/repeat/up ───────────────────────────────

  KeyEventResult _handlePageKeyDown(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyM:
        _playback.toggleMute();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        unawaited(_toggleFullscreen());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        unawaited(_exitFullscreenOrClose());
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handlePageRepeat(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyM:
      case LogicalKeyboardKey.keyF:
      case LogicalKeyboardKey.escape:
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handlePageKeyUp(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyM:
      case LogicalKeyboardKey.keyF:
      case LogicalKeyboardKey.escape:
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── 右方向键 400ms 短按/长按分类器 ────────────────────────

  void _onRightDown() {
    if (_rightPressed) return;
    _rightPressed = true;
    _rightClassifiedAsHold = false;
    _rightHoldTimer = _timerFactory(const Duration(milliseconds: 400), () {
      if (_disposed || !_rightPressed) return;
      _rightClassifiedAsHold = true;
      _rightSpeedLease = _playback.beginTemporarySpeed(3.0);
      _onInteractionChanged();
    });
  }

  void _onRightUp() {
    if (!_rightPressed) return;
    final seek = !_rightClassifiedAsHold;
    _cancelRightState();
    if (seek) _playback.seekRelative(const Duration(seconds: 5));
  }

  /// 右方向键状态唯一收口：取消计时器、复位 pressed/classified、释放 lease。
  ///
  /// 计时器到期即标记为长按，即使 [VideoPlaybackController.beginTemporarySpeed]
  /// 因暂停/结束/错误返回 null，松开也不会补做短按 Seek。focus lost/blur/
  /// retry/dispose 都走这里，且明确不执行短按分支。
  void _cancelRightState() {
    _rightHoldTimer?.cancel();
    _rightHoldTimer = null;
    _rightPressed = false;
    _rightClassifiedAsHold = false;
    final lease = _rightSpeedLease;
    _rightSpeedLease = null;
    if (lease != null) _playback.endTemporarySpeed(lease);
  }

  // ── 鼠标活动、控制栏聚合与光标显隐 ──────────────────────────

  /// 播放状态是否要求保持光标/控件可见（暂停、结束、错误）。
  bool get _playbackKeepsCursorVisible =>
      !_playback.state.isPlaying ||
      _playback.state.hasEnded ||
      _playback.state.hasError;

  /// 任一来源要求保持可见时即停止三秒隐藏。
  bool get _mustStayVisible =>
      _playbackKeepsCursorVisible ||
      _pointerInsideControls ||
      _controlsHaveFocus ||
      _controlsPopupOpen;

  /// 聚合 hover/focus/弹层：只在聚合值 true→false 时调用一次
  /// [VideoPlaybackController.holdControlsVisible]，false→true 时调用一次
  /// `releaseControlsHold`，并同步按真实状态重排光标计时。单一来源退出
  /// 不会错误释放另一来源持有的 hold。
  void _refreshControlsHoldAndCursor() {
    final shouldHold =
        _pointerInsideControls || _controlsHaveFocus || _controlsPopupOpen;
    if (shouldHold && !_holdsPlaybackControls) {
      _holdsPlaybackControls = true;
      _playback.holdControlsVisible();
    } else if (!shouldHold && _holdsPlaybackControls) {
      _holdsPlaybackControls = false;
      _playback.releaseControlsHold();
    }
    _scheduleCursorHide();
  }

  /// 集中安排光标三秒隐藏：需要保持可见时不建计时器并把光标置可见，
  /// 否则从当前时点重启三秒。与共享核心控制栏计时器独立。
  void _scheduleCursorHide() {
    _cursorIdleTimer?.cancel();
    if (_mustStayVisible) {
      _setCursorVisible(true);
      return;
    }
    _cursorIdleTimer = _timerFactory(const Duration(seconds: 3), () {
      if (_mustStayVisible) return;
      _setCursorVisible(false);
    });
  }

  /// 光标可见性唯一写入点：值变化时通知页面重建 MouseRegion cursor。
  void _setCursorVisible(bool visible) {
    if (_isCursorVisible == visible) return;
    _isCursorVisible = visible;
    _onInteractionChanged();
  }

  /// 取消 50ms 滚轮节流。
  void _cancelWheelThrottle() {
    _wheelThrottleTimer?.cancel();
    _wheelThrottleTimer = null;
    _wheelThrottled = false;
  }

  /// 取消光标计时并强制恢复可见光标；dispose 已置位时不释放 hold，
  /// 避免在页面拆除阶段向共享核心反向安排计时器。
  void _cancelCursorVisibility({required bool notify}) {
    _cursorIdleTimer?.cancel();
    _cursorIdleTimer = null;
    if (!_isCursorVisible) {
      _isCursorVisible = true;
      if (notify) _onInteractionChanged();
    }
    if (!_disposed && _holdsPlaybackControls) {
      _holdsPlaybackControls = false;
      _playback.releaseControlsHold();
    }
  }

  // ── 全屏切换与退出 ────────────────────────────────────────

  /// 切换原生全屏；插件失败只显示固定安全文案，不伪造状态、不关闭页面。
  Future<void> _toggleFullscreen() async {
    final result = await _fullscreen.toggle();
    if (!result.succeeded) {
      _playback.showOperationFailure('无法切换全屏');
    }
  }

  /// Escape 回退：当前或期望处于全屏时只退出全屏并留在播放器；
  /// 已是窗口模式时请求关闭页面。
  Future<void> _exitFullscreenOrClose() async {
    if (_fullscreen.actualFullscreen || _fullscreen.desiredFullscreen) {
      await _fullscreen.exitIfFullscreen();
      return;
    }
    await _onRequestClose();
  }
}
