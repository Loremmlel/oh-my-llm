import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../widgets/video_player_controls.dart';

/// 全屏视频播放器。
///
/// Phase 5 完整版：自定义控制栏（倍速、音量、进度条）、
/// 自动横屏、控制栏 3 秒自动隐藏、播放结束处理。
/// 复杂手势留给 Phase 6。
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String fileName;

  /// 控制器工厂，用于测试注入。默认使用 [VideoPlayerController.networkUrl]。
  final VideoPlayerController Function(Uri)? controllerFactory;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    required this.fileName,
    this.controllerFactory,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  // ── 播放器状态 ─────────────────────────────────────────────────

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  // ── 控制栏状态 ─────────────────────────────────────────────────

  bool _controlsVisible = true;
  double _currentSpeed = 1.0;
  double _currentVolume = 1.0;
  Timer? _hideTimer;
  bool _isDragging = false;
  double _dragPositionMs = 0.0;
  double _bufferedPercent = 0.0;
  bool _hasEnded = false;

  // ── 手势状态（Phase 6） ────────────────────────────────────────

  /// 上次 tap 的屏幕 X 坐标（判断左右半屏）
  double? _lastTapPositionDx;

  /// 长按中
  bool _isLongPressing = false;

  /// 长按前的倍速（松手恢复用）
  double _preLongPressSpeed = 1.0;

  /// 水平拖动 seek 中
  bool _isHorizontalDragging = false;

  /// 手势拖动 seek 预览位置
  Duration _seekPreviewPosition = Duration.zero;

  /// 拖动起点位置
  Duration _dragStartPosition = Duration.zero;

  /// 拖动起点 X 坐标
  double _dragStartDx = 0;

  /// 中央提示类型
  CenterHintType _centerHint = CenterHintType.none;

  /// 中央提示自动消失计时器
  Timer? _hintTimer;

  /// 进入手势前的控制栏可见性（用于手势结束后恢复）
  bool? _controlsVisibleBeforeGesture;

  // ── 缓存值 ─────────────────────────────────────────────────────

  /// build 中缓存的屏幕宽度（手势回调中避免使用 MediaQuery）
  double _cachedScreenWidth = 0;

  // ── 从 controller listener 同步的播放状态 ─────────────────────

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // ── 生命周期 ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // 进入时自动横屏，但不锁定——用户旋转手机仍可切回竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 沉浸式 UI（隐藏系统状态栏和导航栏）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 注册生命周期监听（处理前后台切换）
    WidgetsBinding.instance.addObserver(this);
    // 初始化播放器
    _initPlayer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();

    // 先移除监听器，防止后续操作触发 _onControllerUpdate 导致 setState on disposed widget
    _controller?.removeListener(_onControllerUpdate);

    // 如果正在长按中退出页面，恢复原倍速（在移除监听器之后，避免通知触发 setState）
    if (_isLongPressing && _controller != null) {
      _controller!.setPlaybackSpeed(_preLongPressSpeed);
    }

    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // 恢复所有屏幕方向
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── 应用前后台处理 ─────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进入后台时暂停播放，避免后台继续消耗资源
    // 恢复时不自动播放，由用户手动控制
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    }
  }

  // ── 播放器初始化 ───────────────────────────────────────────────

  Future<void> _initPlayer() async {
    // 先清理旧 controller，避免重试时泄漏资源
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;

    // 重置展示状态，避免加载中显示上一次视频的残留数据
    _bufferedPercent = 0.0;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;

    try {
      final factory =
          widget.controllerFactory ?? VideoPlayerController.networkUrl;
      final controller = factory(Uri.parse(widget.videoUrl));
      _controller = controller;
      controller.addListener(_onControllerUpdate);

      await controller.initialize();
      if (!mounted) return;
      // 防止快速重试导致操作已释放的旧 controller（竞态守卫）
      if (controller != _controller) return;

      // 重试时恢复之前的倍速和音量设置（新 controller 默认为 1.0）
      controller.setVolume(_currentVolume);
      controller.setPlaybackSpeed(_currentSpeed);

      controller.play();
      // 基于播放器实际状态决定 _hasEnded，避免覆盖 _onControllerUpdate 的正确检测。
      final videoAlreadyEnded = controller.value.isCompleted &&
          _isNearEnd(controller.value.position, controller.value.duration);
      setState(() {
        _isInitialized = true;
        _hasError = false;
        _errorMessage = null;
        _hasEnded = videoAlreadyEnded;
        _isPlaying = true; // controller.play() 已调用，避免计时器延迟一帧
        // 重试时重置手势状态，避免过期 flag 影响新 controller
        _isLongPressing = false;
        _isHorizontalDragging = false;
      });
      _startHideTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = '视频加载失败: $e';
        _isInitialized = false;
      });
    }
  }

  // ── 播放器状态监听 ─────────────────────────────────────────────

  void _onControllerUpdate() {
    if (!mounted) return;
    final value = _controller?.value;
    if (value == null) return;

    final wasPlaying = _isPlaying;

    setState(() {
      _isPlaying = value.isPlaying;
      _currentPosition = value.position;
      _totalDuration = value.duration;

      // 缓冲进度计算
      final buffered = value.buffered;
      if (buffered.isNotEmpty && value.duration > Duration.zero) {
        _bufferedPercent = (buffered.last.end.inMicroseconds /
                value.duration.inMicroseconds)
            .clamp(0.0, 1.0);
      }

      // 检测播放结束（需确认位置确实在结尾，排除 seek 中转态）
      final atEnd = _isNearEnd(value.position, value.duration);
      if (value.isCompleted && !_hasEnded && atEnd) {
        _hasEnded = true;
        _controlsVisible = true;
        _hideTimer?.cancel();
      }

      // 用户主动暂停时显示控制栏（合并到同一 setState，避免二次重建）
      if (wasPlaying && !value.isPlaying && !_hasEnded) {
        _controlsVisible = true;
      }
    });

    // 计时器管理（无需额外 setState）
    if (wasPlaying && !_isPlaying && !_hasEnded) {
      _hideTimer?.cancel();
    } else if (!wasPlaying && _isPlaying) {
      _startHideTimer();
    }
  }

  // ── 播放控制 ───────────────────────────────────────────────────

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    if (_hasEnded) {
      // 播放结束后重新播放：回到开头
      _controller!.seekTo(Duration.zero);
      _controller!.play();
      setState(() {
        _hasEnded = false;
        _isPlaying = true; // 同步更新，避免 seek 中转态误触发 _hasEnded
      });
    } else if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    // 交互后重置计时器
    _resetHideTimer();
  }

  // ── 倍速 / 音量 ────────────────────────────────────────────────

  void _changeSpeed(double speed) {
    _controller?.setPlaybackSpeed(speed);
    setState(() => _currentSpeed = speed);
    _resetHideTimer();
  }

  void _setVolume(double vol) {
    _controller?.setVolume(vol);
    setState(() => _currentVolume = vol);
    // 不重置计时器：音量弹窗关闭后由 onInteractionEnded 统一处理
  }

  // ── 进度条 Seek ────────────────────────────────────────────────

  /// 将归一化进度 0.0-1.0 转换为毫秒位置。
  double _fractionToMs(double fraction) {
    return (_totalDuration.inMilliseconds * fraction)
        .toDouble()
        .clamp(0, _totalDuration.inMilliseconds.toDouble());
  }

  /// 拖动开始：取消计时器，记录初始位置。
  ///
  /// [fraction] 为归一化位置 0.0-1.0。
  void _onSeekStart(double fraction) {
    // 手势水平拖动活跃时忽略 Slider 事件（两者互斥，Slider 通常因
    // 手势竞技场而胜出，但此处加上防御性 guard 防止竞态）。
    if (_isHorizontalDragging) return;
    _hideTimer?.cancel();
    setState(() {
      _dragPositionMs = _fractionToMs(fraction);
      _isDragging = true;
    });
  }

  /// 拖动中：仅更新 UI 位置，不发送 seek 请求。
  ///
  /// [fraction] 为归一化位置 0.0-1.0。
  void _onSeekUpdate(double fraction) {
    setState(() {
      _dragPositionMs = _fractionToMs(fraction);
    });
  }

  /// 松手：执行实际的 seekTo，恢复计时器。
  void _onSeekEnd() {
    _controller?.seekTo(Duration(milliseconds: _dragPositionMs.round()));
    setState(() => _isDragging = false);
    _resetHideTimer();
  }

  // ── 控制栏显隐 ─────────────────────────────────────────────────

  void _handleTap() {
    if (!mounted) return;
    setState(() => _controlsVisible = !_controlsVisible);
    _resetHideTimer(); // 内部已处理 visible/hidden 两种情况
  }

  /// 启动 3 秒自动隐藏计时器。
  ///
  /// 仅在播放中、未暂停、未结束时启动。
  /// 手势进行期间不启动（避免 _onControllerUpdate 意外重启计时器）。
  void _startHideTimer() {
    _hideTimer?.cancel();
    // 手势进行期间不启动自动隐藏（审阅意见 #11）
    if (_isLongPressing || _isHorizontalDragging) return;
    if (_isPlaying && !_hasEnded) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _controlsVisible = false);
      });
    }
  }

  /// 重置自动隐藏计时器（用户交互后调用）。
  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_controlsVisible) {
      _startHideTimer();
    }
  }

  // ── 播放结束检测助手 ───────────────────────────────────────────

  /// 判断视频位置是否在距结尾 [threshold] 内。
  ///
  /// 对时长 < 500ms 的短视频，阈值 clamp 为 0，避免 `duration - 500ms`
  /// 产生负 Duration 导致 `position >= 负值` 恒为 true。
  bool _isNearEnd(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    final threshold = duration < const Duration(milliseconds: 500)
        ? Duration.zero
        : duration - const Duration(milliseconds: 500);
    return position >= threshold;
  }

  // ── 手势辅助方法（Phase 6） ─────────────────────────────────────

  /// 手势开始时调用：保存控制栏状态并强制隐藏。
  ///
  /// 若已在手势中（[_controlsVisibleBeforeGesture] 非 null）则跳过，
  /// 防止快速连续手势（如双击后 1s 内再次双击）覆盖第一次保存的状态。
  void _beginGesture() {
    if (_controlsVisibleBeforeGesture != null) return;
    _controlsVisibleBeforeGesture = _controlsVisible;
    setState(() => _controlsVisible = false);
    _hideTimer?.cancel();
  }

  /// 手势结束时调用：恢复控制栏状态并重置计时器。
  ///
  /// 播放结束时优先级最高：即使手势前控制栏是隐藏的，也保持可见
  ///（_onControllerUpdate 在播放结束时强制设 _controlsVisible = true）。
  void _endGesture() {
    if (_controlsVisibleBeforeGesture != null) {
      setState(() {
        _controlsVisible = _hasEnded ? true : _controlsVisibleBeforeGesture!;
      });
      _controlsVisibleBeforeGesture = null;
      _resetHideTimer();
    }
  }

  /// 显示中央提示，[onHintDismissed] 在提示 1 秒后自动消失时回调。
  void _showCenterHint(CenterHintType type, {VoidCallback? onHintDismissed}) {
    _hintTimer?.cancel();
    setState(() => _centerHint = type);
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _centerHint = CenterHintType.none);
      onHintDismissed?.call();
    });
  }

  /// 立即隐藏中央提示。
  void _hideCenterHint() {
    _hintTimer?.cancel();
    if (mounted) setState(() => _centerHint = CenterHintType.none);
  }

  // ── 双击手势（Phase 6） ─────────────────────────────────────────

  /// 记录双击按下位置（用于判断左右半屏）。
  void _handleDoubleTapDown(TapDownDetails details) {
    _lastTapPositionDx = details.globalPosition.dx;
  }

  /// 双击：左半屏快退 15s，右半屏快进 15s。
  void _handleDoubleTap() {
    // 通用护栏
    if (_controller == null || !_isInitialized || _hasError) return;

    final isLeftHalf = (_lastTapPositionDx ?? 0) < _cachedScreenWidth / 2;
    final targetPosition = isLeftHalf
        ? _currentPosition - const Duration(seconds: 15)
        : _currentPosition + const Duration(seconds: 15);

    // Duration 没有 clamp 方法，手动夹紧
    final clamped = targetPosition < Duration.zero
        ? Duration.zero
        : (targetPosition > _totalDuration ? _totalDuration : targetPosition);
    _controller!.seekTo(clamped);

    // 手势期间隐藏控制栏，提示消失后恢复
    _beginGesture();
    _showCenterHint(
      isLeftHalf ? CenterHintType.rewind : CenterHintType.fastForward,
      onHintDismissed: _endGesture,
    );
  }

  // ── 长按手势（Phase 6） ─────────────────────────────────────────

  /// 长按开始：切换到 3x 倍速（仅播放中生效，播放结束时不生效）。
  void _handleLongPressStart(LongPressStartDetails details) {
    if (_controller == null || !_isInitialized || _hasError) return;
    if (!_isPlaying || _hasEnded) return;
    _preLongPressSpeed = _currentSpeed;
    _isLongPressing = true;
    _controller!.setPlaybackSpeed(3.0);
    _beginGesture();
    _showCenterHint(CenterHintType.speed);
  }

  /// 长按结束或取消时的公共恢复逻辑。
  void _endLongPress() {
    if (!mounted) return;
    if (!_isLongPressing) return;
    _isLongPressing = false;
    _controller!.setPlaybackSpeed(_preLongPressSpeed);
    _hideCenterHint();
    _endGesture();
  }

  /// 长按结束：恢复原倍速。
  void _handleLongPressEnd(LongPressEndDetails details) {
    _endLongPress();
  }

  /// 长按取消：复用恢复逻辑。
  void _handleLongPressCancel() {
    _endLongPress();
  }

  // ── 水平拖动 Seek（Phase 6） ────────────────────────────────────

  /// 水平拖动开始：记录起点位置和坐标。
  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_controller == null || !_isInitialized || _hasError) return;
    // Slider 正被拖动时不处理手势 drag
    if (_isDragging) return;
    // 防止零时长导致除以零
    if (_totalDuration <= Duration.zero) return;
    _dragStartPosition = _currentPosition;
    _seekPreviewPosition = _currentPosition; // 初始化为当前位置，防止无 DragUpdate 时 seekTo(0)
    _dragStartDx = details.globalPosition.dx;
    _isHorizontalDragging = true;
    _beginGesture();
  }

  /// 水平拖动中：计算预览位置并更新 UI。
  ///
  /// 公式：当前绝对 X - 起始绝对 X = deltaPixels，
  /// seek 偏移 = (deltaPixels / 屏幕宽度) * 视频总时长。
  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    if (!_isHorizontalDragging) return;
    if (_totalDuration.inMilliseconds == 0) return;

    final deltaPixels = details.globalPosition.dx - _dragStartDx;
    final fraction = deltaPixels / _cachedScreenWidth;
    final offsetMs = (fraction * _totalDuration.inMilliseconds).round();
    final targetMs = (_dragStartPosition.inMilliseconds + offsetMs)
        .clamp(0, _totalDuration.inMilliseconds);

    _seekPreviewPosition = Duration(milliseconds: targetMs);
    // 拖动期间取消自动消失计时器（提示应持续显示），
    // 仅在首次进入 seek 模式时触发 setState，后续帧仅更新位置。
    _hintTimer?.cancel();
    if (_centerHint != CenterHintType.seek) {
      setState(() => _centerHint = CenterHintType.seek);
    } else {
      setState(() {}); // 仅重建以反映 _seekPreviewPosition 变化
    }
  }

  /// 水平拖动结束：执行 seekTo。
  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!mounted) return;
    if (!_isHorizontalDragging) return;
    _isHorizontalDragging = false;
    _controller!.seekTo(_seekPreviewPosition);
    _hideCenterHint();
    _endGesture();
  }

  // ── 返回 ───────────────────────────────────────────────────────

  /// 返回按钮回调。仅执行 pop，所有清理由 [dispose] 统一处理。
  void _onBack() {
    Navigator.pop(context);
  }

  // ── 构建 ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 缓存屏幕宽度，手势回调中避免使用 MediaQuery
    _cachedScreenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      // GestureDetector 包裹整个 Stack。
      // 使用 HitTestBehavior.translucent 确保视频画面区域（Texture widget）
      // 的事件能穿透到 GestureDetector。
      body: GestureDetector(
        onTap: _handleTap,
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        onLongPressStart: _handleLongPressStart,
        onLongPressEnd: _handleLongPressEnd,
        onLongPressCancel: _handleLongPressCancel,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // ── 视频画面 ──
            Center(child: _buildBody()),
            // ── 中央提示 ──
            // 可见条件：已初始化 + 无错误 + (已暂停 或 有手势提示)
            VideoCenterHint(
              visible: _isInitialized &&
                  !_hasError &&
                  (!_isPlaying || _centerHint != CenterHintType.none),
              hintType: _centerHint,
              seekPosition: _seekPreviewPosition,
              showPauseIcon:
                  _isInitialized && !_hasError && !_isPlaying,
            ),
            // ── 顶部控制栏 ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    // 顶部向下渐变
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: VideoTopBar(
                        fileName: widget.fileName,
                        playbackSpeed: _currentSpeed,
                        volume: _currentVolume,
                        onBack: _onBack,
                        onSpeedChanged: _changeSpeed,
                        onVolumeChanged: _setVolume,
                        onInteractionStarted: () => _hideTimer?.cancel(),
                        onInteractionEnded: _resetHideTimer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── 底部控制栏 ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    // 底部向上渐变
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: VideoBottomBar(
                        isPlaying: _isPlaying,
                        hasEnded: _hasEnded,
                        currentPosition: _currentPosition,
                        totalDuration: _totalDuration,
                        bufferedPercent: _bufferedPercent,
                        isDragging: _isDragging,
                        dragPosition:
                            Duration(milliseconds: _dragPositionMs.round()),
                        onPlayPause: _togglePlayPause,
                        onSeekStart: _onSeekStart,
                        onSeekUpdate: _onSeekUpdate,
                        onSeekEnd: _onSeekEnd,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 视频主体 ───────────────────────────────────────────────────

  Widget _buildBody() {
    // 错误状态
    if (_hasError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 64),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? '视频加载失败',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _errorMessage = null;
              });
              _initPlayer();
            },
            child: const Text('重试'),
          ),
        ],
      );
    }

    // 加载状态
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    // 视频画面
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}
