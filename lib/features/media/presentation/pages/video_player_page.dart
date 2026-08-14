import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import '../widgets/video_player_controls.dart';
import 'media_video_controller_factory.dart';
import 'mobile_video_interaction_controller.dart';
import 'video_playback_controller.dart';
import 'video_playback_state.dart';

/// 全屏视频播放器。
///
/// 应用暂停只暂停播放；控制器和计时器仅在路由 dispose 时释放。
/// 播放源是解析完成的 [MediaResource]，平台控制器经
/// [controllerFactory] 创建（测试注入 Fake 的 seam）。
/// 页面只负责组合共享播放核心、移动端输入层、控制栏与焦点管理，
/// 不再直接调用底层播放器命令。
class VideoPlayerPage extends StatefulWidget {
  final MediaResource resource;
  final String fileName;

  /// 平台控制器工厂：默认按资源类型选择本地/网络数据源。
  final MediaVideoControllerFactory controllerFactory;

  const VideoPlayerPage({
    super.key,
    required this.resource,
    required this.fileName,
    this.controllerFactory = createMediaVideoController,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  late final VideoPlaybackController _playback;
  late final MobileVideoInteractionController _mobile;

  /// 播放表面焦点：键盘快捷键只在它拥有主焦点时生效。
  final _playerFocusNode = FocusNode();

  /// top/bottom 控制栏祖先焦点节点：只观察 descendant focus，自身不可请求焦点。
  final _topControlsFocusNode = FocusNode(canRequestFocus: false);
  final _bottomControlsFocusNode = FocusNode(canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    _playback = VideoPlaybackController(
      resource: widget.resource,
      controllerFactory: widget.controllerFactory,
      onStateChanged: _handleStateChanged,
    );
    _mobile = MobileVideoInteractionController(playback: _playback);

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

    _initPlayer();
  }

  /// 按当前 [MediaResource] 创建并初始化播放器；重试与首次进入共用同一条路径。
  void _initPlayer() {
    _playback.initialize();
  }

  /// 顶部关闭按钮与 Escape 共用的页面关闭路径。
  void _popVideo() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerFocusNode.dispose();
    _topControlsFocusNode.dispose();
    _bottomControlsFocusNode.dispose();
    _mobile.dispose();
    _playback.dispose();

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
    final controlsHidden = !_playback.state.controlsVisible;
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
      _playback.holdControlsVisible();
    } else {
      _playback.releaseControlsHold();
    }
  }

  /// 播放表面按键：只响应 KeyDown（忽略 KeyUp/KeyRepeat），
  /// 且仅在表面拥有主焦点时生效，其余情况交还平台默认行为。
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_playerFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _popVideo();
      return KeyEventResult.handled;
    }
    return _mobile.handleSurfaceKey(event);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused) {
      _playback.onAppLifecyclePaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _playback.state;
    _mobile.updateScreenWidth(MediaQuery.sizeOf(context).width);

    return Scaffold(
      backgroundColor: Colors.black,
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            Positioned.fill(child: _buildPlaybackInteractionLayer(s)),
            IgnorePointer(
              child: Center(
                child: VideoCenterHint(
                  visible:
                      s.isInitialized &&
                      !s.hasError &&
                      (!s.isPlaying || s.centerFeedback != null),
                  feedback: s.centerFeedback,
                  showPauseIcon: s.isInitialized && !s.hasError && !s.isPlaying,
                ),
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
    );
  }

  /// 播放交互层：播放表面 + 全屏手势 overlay。
  ///
  /// 手势 overlay 与控制栏是兄弟层：控制栏绘制在 overlay 之后，hit test
  /// 优先命中控制栏，按钮 tap 不再被双击识别器的窗口拖延。overlay 左右
  /// 收缩出 systemGestureInsets，边缘拖动让位给系统手势（如 Android 返回
  /// 手势），`systemGestureInsets` 只影响命中区域、不缩小视频画面。
  /// 播放表面等比居中、不随视口拉伸；错误/加载状态不建 overlay，
  /// 重试按钮可立即点击。
  Widget _buildPlaybackInteractionLayer(VideoPlaybackState s) {
    final playbackSurface = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: _buildPlaybackSurface(s),
    );
    if (!s.isInitialized || s.hasError) return playbackSurface;

    final insets = MediaQuery.systemGestureInsetsOf(context);
    return Stack(
      // 播放表面按 16:9 等比布局并居中（loose fit，不随视口拉伸）；
      // Positioned 手势 overlay 始终铺满全屏，系统边缘内仍可命中
      alignment: Alignment.center,
      children: [
        playbackSurface,
        Positioned(
          left: insets.left,
          right: insets.right,
          top: 0,
          bottom: 0,
          child: RawGestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () => TapGestureRecognizer(debugOwner: this),
                    (instance) => instance.onTap = _mobile.handleTap,
                  ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    DoubleTapGestureRecognizer
                  >(() => DoubleTapGestureRecognizer(debugOwner: this), (
                    instance,
                  ) {
                    instance.onDoubleTapDown = _mobile.handleDoubleTapDown;
                    instance.onDoubleTap = _mobile.handleDoubleTap;
                  }),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(() => LongPressGestureRecognizer(debugOwner: this), (
                    instance,
                  ) {
                    instance.onLongPressStart = _mobile.handleLongPressStart;
                    instance.onLongPressEnd = _mobile.handleLongPressEnd;
                    instance.onLongPressCancel = _mobile.handleLongPressCancel;
                  }),
              CancelAwareHorizontalDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    CancelAwareHorizontalDragRecognizer
                  >(
                    () => CancelAwareHorizontalDragRecognizer(debugOwner: this),
                    (instance) {
                      instance.onStart = _mobile.handleHorizontalDragStart;
                      instance.onUpdate = _mobile.handleHorizontalDragUpdate;
                      instance.onEnd = _mobile.handleHorizontalDragEnd;
                      instance.onCancel = _mobile.handleHorizontalDragCancel;
                    },
                  ),
            },
          ),
        ),
      ],
    );
  }

  /// 已初始化的播放表面：可聚焦、可激活、带键盘快捷键与焦点边框。
  Widget _buildPlaybackSurface(VideoPlaybackState s) {
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
        ? (controlsVisible ? '播放已结束，播放控件已显示' : '播放已结束，播放控件已隐藏')
        : s.isPlaying
        ? (controlsVisible ? '正在播放，播放控件已显示' : '正在播放，播放控件已隐藏')
        : (controlsVisible ? '已暂停，播放控件已显示' : '已暂停，播放控件已隐藏');
    final hint = controlsVisible
        ? '激活以隐藏播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒'
        : '激活以显示播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒';

    return Semantics(
      label: '视频播放器：${widget.fileName}',
      value: valueText,
      hint: hint,
      button: true,
      enabled: true,
      onTap: _mobile.handleTap,
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
  Widget _buildErrorState(VideoPlaybackState s) {
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
          ElevatedButton(onPressed: _initPlayer, child: const Text('重试')),
        ],
      ),
    );
  }

  /// 顶部控制栏：隐藏时同时退出 pointer/focus/semantics，
  /// 但祖先 FocusNode 始终存在以观察 descendant focus。
  Widget _buildTopControls(VideoPlaybackState s) {
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
                      playbackSpeed: s.persistentSpeed,
                      volume: s.volume,
                      onBack: _popVideo,
                      onSpeedChanged: _playback.setPersistentSpeed,
                      onVolumeChanged: _playback.setVolume,
                      onInteractionStarted: _playback.holdControlsVisible,
                      onInteractionEnded: _playback.releaseControlsHold,
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
  ///
  /// Slider 是长按拖动目标，与系统手势（返回/边缘滑动）竞争触摸；
  /// 左右按 systemGestureInsets 收缩命中区域让位给系统手势，
  /// 渐变背景仍保持 edge-to-edge。
  Widget _buildBottomControls(VideoPlaybackState s) {
    final gestureInsets = MediaQuery.systemGestureInsetsOf(context);
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
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: gestureInsets.left,
                        right: gestureInsets.right,
                      ),
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
                        onPlayPause: _playback.togglePlayPause,
                        onSeekStart: _playback.onSeekStart,
                        onSeekUpdate: _playback.onSeekUpdate,
                        onSeekEnd: _playback.onSeekEnd,
                      ),
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
