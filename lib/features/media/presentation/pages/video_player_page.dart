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
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerUpdate);
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
      setState(() {
        _isInitialized = true;
        _hasError = false;
        _errorMessage = null;
        _hasEnded = false;
        _isPlaying = true; // controller.play() 已调用，避免计时器延迟一帧
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
      final atEnd = value.duration > Duration.zero &&
          value.position >=
              value.duration - const Duration(milliseconds: 500);
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
    setState(() => _controlsVisible = !_controlsVisible);
    _resetHideTimer(); // 内部已处理 visible/hidden 两种情况
  }

  /// 启动 3 秒自动隐藏计时器。
  ///
  /// 仅在播放中、未暂停、未结束时启动。
  void _startHideTimer() {
    _hideTimer?.cancel();
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

  // ── 返回 ───────────────────────────────────────────────────────

  /// 返回按钮回调。仅执行 pop，所有清理由 [dispose] 统一处理。
  void _onBack() {
    Navigator.pop(context);
  }

  // ── 构建 ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // GestureDetector 包裹整个 Stack，确保黑边区域也能响应点击
      body: GestureDetector(
        onTap: _handleTap,
        child: Stack(
          children: [
            // ── 视频画面 ──
            Center(child: _buildBody()),
            // ── 中央提示 ──
            VideoCenterHint(
              visible:
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
