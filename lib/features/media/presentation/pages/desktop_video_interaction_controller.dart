import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'video_player_platform_bindings.dart';
import 'video_playback_controller.dart';

/// Windows 桌面键盘输入状态机。
///
/// 只把按键 down/repeat/up 序列翻译为共享核心的公开命令与全屏窄端口，不读取
/// BuildContext/FocusNode/Navigator，不保存播放位置、音量、常驻倍速等事实值。
/// 右方向键的短按/长按互斥、400ms 计时器与临时倍速 lease 是本 controller 的
/// 私有瞬态，不进入共享状态。
///
/// 作用域约定：播放表面主焦点下的 Space/媒体键/Enter/四方向键走
/// [handleSurfaceKey]；视频页面且无更高层弹层时的 M/F/Escape 走 [handlePageKey]。
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

  // ── 公开入口 ──────────────────────────────────────────────

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

  /// 播放表面失去主焦点：取消 pending/hold，不执行短按 Seek。
  void onSurfaceFocusLost() => _cancelRightState();

  /// 窗口失焦：取消 pending/hold 并释放临时倍速，不等待可能丢失的 KeyUp。
  void onWindowBlur() => _cancelRightState();

  /// 播放结束：hold 收口，释放临时倍速，不执行短按 Seek。
  void onPlaybackEnded() => _cancelRightState();

  /// 初始化重试前取消进行中的右方向键状态。
  void cancelForRetry() => _cancelRightState();

  /// 页面销毁：幂等清理，取消计时器并释放临时倍速。
  void dispose() {
    _disposed = true;
    _cancelRightState();
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
