import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../widgets/video_player_controls.dart';
import 'video_player_gesture.dart';
import 'video_player_state.dart';

/// 全屏视频播放器。
///
/// 应用暂停只暂停播放；控制器和计时器仅在路由 dispose 时释放。
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
  final _gesture = VideoPlayerGestureController();

  /// 播放表面焦点：键盘快捷键只在它拥有主焦点时生效。
  final _playerFocusNode = FocusNode();

  /// top/bottom 控制栏祖先焦点节点：只观察 descendant focus，自身不可请求焦点。
  final _topControlsFocusNode = FocusNode(canRequestFocus: false);
  final _bottomControlsFocusNode = FocusNode(canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    _gesture.onStateChanged = _handleStateChanged;
    _gesture.onBackPressed = () => Navigator.pop(context);
    _gesture.setMounted(true);

    // 焦点边框随 focus 变化重建；控制栏焦点变化驱动 hide timer。
    _playerFocusNode.addListener(() => setState(() {}));
    _topControlsFocusNode.addListener(_onControlsFocusChanged);
    _bottomControlsFocusNode.addListener(_onControlsFocusChanged);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);

    final factory =
        widget.controllerFactory ?? VideoPlayerController.networkUrl;
    _gesture.initPlayer(Uri.parse(widget.videoUrl), factory);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerFocusNode.dispose();
    _topControlsFocusNode.dispose();
    _bottomControlsFocusNode.dispose();
    _gesture.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// 状态变化回调：控制栏被隐藏时若控制内仍有键盘焦点，
  /// 下一帧把焦点恢复到播放表面，禁止留下不可见焦点。
  void _handleStateChanged() {
    if (!mounted) return;
    final controlsHidden = !_gesture.state.controlsVisible;
    final controlsFocused =
        _topControlsFocusNode.hasFocus || _bottomControlsFocusNode.hasFocus;
    if (controlsHidden && controlsFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playerFocusNode.requestFocus();
      });
    }
    setState(() {});
  }

  /// 焦点进入任一控制栏时暂停自动隐藏；全部离开后恢复原计时。
  void _onControlsFocusChanged() {
    if (_topControlsFocusNode.hasFocus || _bottomControlsFocusNode.hasFocus) {
      _gesture.onControlsFocusEnter();
    } else {
      _gesture.onControlsFocusExit();
    }
  }

  /// 播放表面按键：只响应 KeyDown（忽略 KeyUp/KeyRepeat），
  /// 且仅在表面拥有主焦点时生效，其余情况交还平台默认行为。
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_playerFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
        _gesture.handleTap();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _gesture.togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _gesture.seekRelative(const Duration(seconds: -15));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _gesture.seekRelative(const Duration(seconds: 15));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _gesture.onBack();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused) {
      _gesture.onAppLifecyclePaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _gesture.state;
    s.cachedScreenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: GestureDetector(
          onTap: _gesture.handleTap,
          onDoubleTapDown: _gesture.handleDoubleTapDown,
          onDoubleTap: _gesture.handleDoubleTap,
          onLongPressStart: _gesture.handleLongPressStart,
          onLongPressEnd: _gesture.handleLongPressEnd,
          onLongPressCancel: _gesture.handleLongPressCancel,
          onHorizontalDragStart: _gesture.handleHorizontalDragStart,
          onHorizontalDragUpdate: _gesture.handleHorizontalDragUpdate,
          onHorizontalDragEnd: _gesture.handleHorizontalDragEnd,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: _buildPlaybackSurface(s),
              ),
              Center(
                child: VideoCenterHint(
                  visible:
                      s.isInitialized &&
                      !s.hasError &&
                      (!s.isPlaying || s.centerHint != CenterHintType.none),
                  hintType: s.centerHint,
                  seekPosition: s.seekPreviewPosition,
                  showPauseIcon: s.isInitialized && !s.hasError && !s.isPlaying,
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: _buildTopControls(s),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: _buildBottomControls(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 已初始化的播放表面：可聚焦、可激活、带键盘快捷键与焦点边框。
  Widget _buildPlaybackSurface(VideoPlayerUiState s) {
    if (s.hasError) return _buildErrorState(s);
    if (!s.isInitialized) {
      return Semantics(
        label: '正在加载视频',
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }

    final ctrl = s.controller;
    if (ctrl == null) return const SizedBox.shrink();

    final controlsVisible = s.controlsVisible;
    final valueText = s.hasEnded
        ? '播放已结束，播放控件已显示'
        : s.isPlaying
        ? (controlsVisible ? '正在播放，播放控件已显示' : '正在播放，播放控件已隐藏')
        : '已暂停，播放控件已显示';
    final hint = controlsVisible
        ? '激活以隐藏播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒'
        : '激活以显示播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒';

    return Semantics(
      label: '视频播放器：${widget.fileName}',
      value: valueText,
      hint: hint,
      button: true,
      enabled: true,
      onTap: _gesture.handleTap,
      child: Focus(
        focusNode: _playerFocusNode,
        onKeyEvent: _handlePlayerKeyEvent,
        child: Container(
          decoration: BoxDecoration(
            // 聚焦时在播放区域边缘显示主题 primary 色焦点边框。
            border: Border.all(
              color: _playerFocusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        ),
      ),
    );
  }

  /// 错误状态：单一 live status 节点；可见 icon/text 排除重复语义，
  /// 「重试」保留 ElevatedButton 自动语义。
  Widget _buildErrorState(VideoPlayerUiState s) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: s.errorMessage ?? '视频加载失败',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.error_outline, color: Colors.white54, size: 64),
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: Text(
              s.errorMessage ?? '视频加载失败',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final factory =
                  widget.controllerFactory ?? VideoPlayerController.networkUrl;
              _gesture.initPlayer(Uri.parse(widget.videoUrl), factory);
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 顶部控制栏：隐藏时同时退出 pointer/focus/semantics，
  /// 但祖先 FocusNode 始终存在以观察 descendant focus。
  Widget _buildTopControls(VideoPlayerUiState s) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Focus(
        focusNode: _topControlsFocusNode,
        child: ExcludeFocus(
          excluding: !s.controlsVisible,
          child: ExcludeSemantics(
            excluding: !s.controlsVisible,
            child: IgnorePointer(
              ignoring: !s.controlsVisible,
              child: AnimatedOpacity(
                opacity: s.controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
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
                      playbackSpeed: s.currentSpeed,
                      volume: s.currentVolume,
                      onBack: _gesture.onBack,
                      onSpeedChanged: _gesture.changeSpeed,
                      onVolumeChanged: _gesture.setVolume,
                      onInteractionStarted: _gesture.onControlsFocusEnter,
                      onInteractionEnded: _gesture.onControlsFocusExit,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部控制栏：同 [_buildTopControls] 的退出策略。
  Widget _buildBottomControls(VideoPlayerUiState s) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Focus(
        focusNode: _bottomControlsFocusNode,
        child: ExcludeFocus(
          excluding: !s.controlsVisible,
          child: ExcludeSemantics(
            excluding: !s.controlsVisible,
            child: IgnorePointer(
              ignoring: !s.controlsVisible,
              child: AnimatedOpacity(
                opacity: s.controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
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
                      isPlaying: s.isPlaying,
                      hasEnded: s.hasEnded,
                      currentPosition: s.currentPosition,
                      totalDuration: s.totalDuration,
                      bufferedPercent: s.bufferedPercent,
                      isDragging: s.isDragging,
                      dragPosition: Duration(
                        milliseconds: s.dragPositionMs.round(),
                      ),
                      onPlayPause: _gesture.togglePlayPause,
                      onSeekStart: _gesture.onSeekStart,
                      onSeekUpdate: _gesture.onSeekUpdate,
                      onSeekEnd: _gesture.onSeekEnd,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
