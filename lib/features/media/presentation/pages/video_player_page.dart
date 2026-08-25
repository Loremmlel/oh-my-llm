import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';

import '../widgets/video_player_controls.dart';
import 'desktop_video_interaction_controller.dart';
import 'media_video_controller_factory.dart';
import 'mobile_video_interaction_controller.dart';
import 'video_playback_controller.dart';
import 'video_playback_state.dart';
import 'video_player_platform_bindings.dart';

/// 全屏视频播放器。
///
/// 应用暂停只暂停播放；控制器和计时器仅在路由 dispose 时释放。
/// 播放源是解析完成的 [MediaResource]，平台控制器经
/// [controllerFactory] 创建（测试注入 Fake 的 seam）。
/// 页面只负责组合共享播放核心、当前平台输入层、控制栏与焦点管理，
/// 不再直接调用底层播放器命令或平台系统 UI。
class VideoPlayerPage extends StatefulWidget {
  final MediaResource resource;
  final String fileName;

  /// 平台控制器工厂：默认按资源类型选择本地/网络数据源。
  final MediaVideoControllerFactory controllerFactory;

  /// 页面级平台 bindings 工厂：一次生命周期调用一次，生成当前平台的
  /// Mobile/Desktop bindings。由 app composition 注入，测试显式传 Fake。
  final VideoPlayerPlatformBindingsFactory platformBindingsFactory;

  const VideoPlayerPage({
    super.key,
    required this.resource,
    required this.fileName,
    required this.platformBindingsFactory,
    this.controllerFactory = createMediaVideoController,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  late final VideoPlaybackController _playback;
  late final VideoPlayerPlatformBindings _bindings;
  MobileVideoInteractionController? _mobile;
  DesktopVideoInteractionController? _desktop;

  /// 播放表面焦点：键盘快捷键只在它拥有主焦点时生效。
  final _playerFocusNode = FocusNode();

  /// 页面级按键作用域：Desktop 的 M/F/Escape 只在无更高层弹层时由此处理。
  final _pageFocusNode = FocusNode(canRequestFocus: false);

  /// top/bottom 控制栏祖先焦点节点：只观察 descendant focus，自身不可请求焦点。
  final _topControlsFocusNode = FocusNode(canRequestFocus: false);
  final _bottomControlsFocusNode = FocusNode(canRequestFocus: false);

  /// Mobile 控制栏聚合焦点的上次值，只在进入/离开边沿更新共享 hold。
  bool _mobileControlsHaveFocus = false;

  /// Desktop 初始化成功后已请求过一次表面焦点，重试后重新请求。
  bool _desktopFocusedAfterInit = false;

  /// 关闭流程进行中：阻止同一关闭命令被多次触发。
  bool _closing = false;

  /// 关闭流程已完成系统 UI / 全屏恢复；dispose 据此跳过重复 fallback。
  bool _restoreCompleted = false;

  /// 真正 pop 的短暂放行标志：恢复完成后置位，让 PopScope 允许本次 pop。
  bool _allowPop = false;

  /// 销毁进行中：dispose 释放临时倍速 lease 会触发状态回调，用该守卫阻止
  /// 已进入销毁流程的 State 再次 setState（此时 element 已标记 defunct）。
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _playback = VideoPlaybackController(
      resource: widget.resource,
      controllerFactory: widget.controllerFactory,
      onStateChanged: _handleStateChanged,
    );
    // 页面一次生命周期只创建一种 bindings：Android 建 Mobile、Windows 建
    // Desktop，两个输入 controller 不同时存活。
    _bindings = widget.platformBindingsFactory();
    switch (_bindings) {
      case MobileVideoPlayerBindings(:final systemUi):
        _mobile = MobileVideoInteractionController(playback: _playback);
        unawaited(systemUi.enter());
      case DesktopVideoPlayerBindings(:final fullscreen):
        _desktop = DesktopVideoInteractionController(
          playback: _playback,
          fullscreen: fullscreen,
          onRequestClose: _requestClose,
          onInteractionChanged: _handleStateChanged,
        );
        unawaited(fullscreen.initializeSession());
    }

    // 焦点边框随 focus 变化重建；表面失焦时通知 Desktop 取消在途输入；
    // 控制栏焦点变化驱动 hide timer。
    _playerFocusNode.addListener(_onPlayerFocusChanged);
    _topControlsFocusNode.addListener(_onControlsFocusChanged);
    _bottomControlsFocusNode.addListener(_onControlsFocusChanged);

    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  /// 按当前 [MediaResource] 创建并初始化播放器；重试与首次进入共用同一条路径。
  void _initPlayer() {
    _desktopFocusedAfterInit = false;
    _desktop?.cancelForRetry();
    _playback.initialize();
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _playerFocusNode.dispose();
    _pageFocusNode.dispose();
    _topControlsFocusNode.dispose();
    _bottomControlsFocusNode.dispose();
    _desktop?.dispose();
    _mobile?.dispose();
    _playback.dispose();
    if (!_restoreCompleted) {
      // 外部强制移除路由的兜底：幂等恢复系统 UI / 全屏会话，不得 await。
      final bindings = _bindings;
      if (bindings is DesktopVideoPlayerBindings) {
        unawaited(bindings.fullscreen.restoreAndDispose());
      } else if (bindings is MobileVideoPlayerBindings) {
        unawaited(bindings.systemUi.restore());
      }
    }
    super.dispose();
  }

  /// 顶部关闭、windowed Escape、系统返回与 GoRouter pop 共用的关闭路径。
  ///
  /// 先等待平台会话恢复（桌面全屏恢复 / 移动系统 UI 恢复），再把 PopScope
  /// 放行状态置位并等待一帧，最后执行真正的 route pop。等待 [endOfFrame]
  /// 只用于让 `PopScope.canPop` 的放行状态进入树，不是通用异步 flush；
  /// 恢复失败仍继续 pop，不把用户困在播放器。
  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    final bindings = _bindings;
    try {
      if (bindings is DesktopVideoPlayerBindings) {
        await bindings.fullscreen.restoreAndDispose();
      } else if (bindings is MobileVideoPlayerBindings) {
        await bindings.systemUi.restore();
      }
    } catch (_) {
      // 恢复失败（如 Android 系统 UI 平台通道异常）不阻塞退出：吞掉异常后
      // 仍放行 pop，与桌面侧 restoreAndDispose 内部捕获的保证一致，避免
      // _closing 残留把用户困在播放器。
    } finally {
      _restoreCompleted = true;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _handlePopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) return;
    unawaited(_requestClose());
  }

  /// 状态变化回调：Desktop 初始化成功后在下一帧自动聚焦播放表面；
  /// 控制栏被隐藏时若控制内仍有键盘焦点，下一帧把焦点恢复到播放表面。
  /// 播放状态每次变化都转发给 Desktop 控制器，由其自行决定是否重排光标计时。
  void _handleStateChanged() {
    if (!mounted || _disposing) return;
    _desktop?.onPlaybackStateChanged();
    final s = _playback.state;
    final desktop = _desktop;
    if (desktop != null &&
        !_desktopFocusedAfterInit &&
        s.isInitialized &&
        !s.hasError) {
      _desktopFocusedAfterInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _playerFocusNode.requestFocus();
        }
      });
    }
    final controlsHidden = !s.controlsVisible;
    final controlsFocused =
        _topControlsFocusNode.hasFocus || _bottomControlsFocusNode.hasFocus;
    if (controlsHidden && controlsFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playerFocusNode.requestFocus();
      });
    }
    setState(() {});
  }

  /// 播放表面焦点变化：边框随焦点重建；失焦时通知 Desktop 取消在途方向键。
  void _onPlayerFocusChanged() {
    setState(() {});
    if (!_playerFocusNode.hasPrimaryFocus) {
      _desktop?.onSurfaceFocusLost();
    }
  }

  /// 焦点进入任一控制栏时暂停自动隐藏；全部离开后恢复原计时。
  ///
  /// Desktop 由桌面控制器聚合 hover/focus/弹层并作为 hold 的唯一 owner，
  /// 页面只转发组合后的焦点事实；Mobile 维持原来的直接 hold/release。
  void _onControlsFocusChanged() {
    final hasFocus =
        _topControlsFocusNode.hasFocus || _bottomControlsFocusNode.hasFocus;
    final desktop = _desktop;
    if (desktop != null) {
      desktop.onControlsFocusChanged(hasFocus);
      return;
    }
    if (hasFocus == _mobileControlsHaveFocus) return;
    _mobileControlsHaveFocus = hasFocus;
    if (hasFocus) {
      _playback.holdControlsVisible();
    } else {
      _playback.releaseControlsHold();
    }
  }

  /// 弹层/菜单打开：Desktop 交给桌面控制器持有控制栏，Mobile 直接 hold。
  void _handleControlsInteractionStarted() {
    final desktop = _desktop;
    if (desktop != null) {
      desktop.onControlsPopupOpened();
    } else {
      _playback.holdControlsVisible();
    }
  }

  /// 弹层/菜单关闭：Desktop 依据真实 focus/hover 重新计算，Mobile 直接 release。
  ///
  /// Desktop 弹层关闭后焦点通常留在控制栏锚点按钮，使控制栏保持 held 且
  /// `_mustStayVisible` 恒真，光标永不自动隐藏；这里在下一帧把主焦点还给
  /// 播放表面，让控制栏焦点事实归零、三秒自动隐藏重新生效。
  void _handleControlsInteractionEnded() {
    final desktop = _desktop;
    if (desktop != null) {
      desktop.onControlsPopupClosed();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playerFocusNode.requestFocus();
      });
    } else {
      _playback.releaseControlsHold();
    }
  }

  /// 控制栏内部焦点变化转发给桌面控制器（与页面组合焦点事实一致，幂等）。
  void _handleDesktopControlsFocusChanged(bool focused) {
    _desktop?.onControlsFocusChanged(focused);
  }

  /// 播放表面按键：Desktop 直接交给桌面状态机；Mobile 只在表面拥有主焦点
  /// 时响应 Escape 关闭与 Enter/Space/左右方向键。
  KeyEventResult _handleSurfaceKeyEvent(FocusNode node, KeyEvent event) {
    final desktop = _desktop;
    if (desktop != null) return desktop.handleSurfaceKey(event);
    final mobile = _mobile;
    if (mobile == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_playerFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_requestClose());
      return KeyEventResult.handled;
    }
    return mobile.handleSurfaceKey(event);
  }

  /// 页面级按键：Desktop 的 M/F/Escape 在事件冒泡到视频页时处理；
  /// Mobile 无页面级快捷键。弹层持有焦点时事件先被弹层消费，不会到达这里。
  KeyEventResult _handlePageKeyEvent(FocusNode node, KeyEvent event) {
    final desktop = _desktop;
    if (desktop == null) return KeyEventResult.ignored;
    return desktop.handlePageKey(event);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      _playback.onAppLifecyclePaused();
      _desktop?.onWindowBlur();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _playback.state;
    _mobile?.updateScreenWidth(MediaQuery.sizeOf(context).width);

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: _handlePopInvokedWithResult,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          // 页面级按键作用域不参与 focus 语义：canRequestFocus 为 false，
          // includeSemantics 关闭避免在语义树中生成合并节点干扰播放表面。
          focusNode: _pageFocusNode,
          includeSemantics: false,
          onKeyEvent: _handlePageKeyEvent,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Stack(
              children: [
                Positioned.fill(child: _buildInteractionLayer(s)),
                IgnorePointer(
                  child: Center(
                    child: VideoCenterHint(
                      visible:
                          s.isInitialized &&
                          !s.hasError &&
                          (!s.isPlaying || s.centerFeedback != null),
                      feedback: s.centerFeedback,
                      showPauseIcon:
                          s.isInitialized && !s.hasError && !s.isPlaying,
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
        ),
      ),
    );
  }

  /// 按当前平台 bindings 构建交互层：Mobile 保留触摸手势，Desktop 只保留
  /// 单击/双击基础层（鼠标活动、光标与滚轮由后续任务扩展）。
  Widget _buildInteractionLayer(VideoPlaybackState s) {
    return switch (_bindings) {
      MobileVideoPlayerBindings() => _buildMobileInteractionLayer(s),
      DesktopVideoPlayerBindings() => _buildDesktopInteractionLayer(s),
    };
  }

  /// 移动端交互层：播放表面 + 全屏手势 overlay。
  ///
  /// 手势 overlay 与控制栏是兄弟层：控制栏绘制在 overlay 之后，hit test
  /// 优先命中控制栏，按钮 tap 不再被双击识别器的窗口拖延。overlay 左右
  /// 收缩出 systemGestureInsets，边缘拖动让位给系统手势（如 Android 返回
  /// 手势），`systemGestureInsets` 只影响命中区域、不缩小视频画面。
  /// 播放表面等比居中、不随视口拉伸；错误/加载状态不建 overlay，
  /// 重试按钮可立即点击。
  Widget _buildMobileInteractionLayer(VideoPlaybackState s) {
    final playbackSurface = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: _buildPlaybackSurface(s),
    );
    if (!s.isInitialized || s.hasError) return playbackSurface;
    final mobile = _mobile;
    if (mobile == null) return playbackSurface;

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
                    (instance) => instance.onTap = mobile.handleTap,
                  ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    DoubleTapGestureRecognizer
                  >(() => DoubleTapGestureRecognizer(debugOwner: this), (
                    instance,
                  ) {
                    instance.onDoubleTapDown = mobile.handleDoubleTapDown;
                    instance.onDoubleTap = mobile.handleDoubleTap;
                  }),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(() => LongPressGestureRecognizer(debugOwner: this), (
                    instance,
                  ) {
                    instance.onLongPressStart = mobile.handleLongPressStart;
                    instance.onLongPressEnd = mobile.handleLongPressEnd;
                    instance.onLongPressCancel = mobile.handleLongPressCancel;
                  }),
              CancelAwareHorizontalDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    CancelAwareHorizontalDragRecognizer
                  >(
                    () => CancelAwareHorizontalDragRecognizer(debugOwner: this),
                    (instance) {
                      instance.onStart = mobile.handleHorizontalDragStart;
                      instance.onUpdate = mobile.handleHorizontalDragUpdate;
                      instance.onEnd = mobile.handleHorizontalDragEnd;
                      instance.onCancel = mobile.handleHorizontalDragCancel;
                    },
                  ),
            },
          ),
        ),
      ],
    );
  }

  /// 桌面交互层：播放表面 + 鼠标活动/光标 + 滚轮 + 单击/双击 overlay。
  ///
  /// 单击播放/暂停并把焦点恢复到播放表面，双击切换原生全屏；不安装移动端
  /// 双击 Seek、长按倍速与横拖 Seek。overlay 与控制栏是兄弟层，控制栏绘制
  /// 在其上，优先命中。鼠标活动经 [MouseRegion] 转发给桌面控制器，滚轮经
  /// [Listener] 转发，光标按 `isCursorVisible` 选择 basic/none。
  Widget _buildDesktopInteractionLayer(VideoPlaybackState s) {
    final playbackSurface = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: _buildPlaybackSurface(s),
    );
    final desktop = _desktop;
    if (!s.isInitialized || s.hasError || desktop == null) {
      return playbackSurface;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        playbackSurface,
        Positioned.fill(
          child: MouseRegion(
            cursor: desktop.isCursorVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onEnter: (_) => desktop.onPointerActivity(),
            onHover: (_) => desktop.onPointerActivity(),
            child: Listener(
              // opaque 保证滚轮事件命中本 overlay：MouseRegion 默认 opaque
              // 会吞掉对 deferToChild 子树的命中，导致 onPointerSignal 收不到。
              behavior: HitTestBehavior.opaque,
              onPointerSignal: desktop.handlePointerSignal,
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.translucent,
                onTap: _handleDesktopSurfaceTap,
                onDoubleTap: () => unawaited(_toggleDesktopFullscreen()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Desktop 画面单击：鼠标活动显示控件与光标、恢复表面焦点并切换播放/暂停。
  void _handleDesktopSurfaceTap() {
    final desktop = _desktop;
    desktop?.onPointerActivity();
    _playerFocusNode.requestFocus();
    _playback.togglePlayPause();
  }

  /// 双击切换原生全屏：插件失败只显示固定安全文案，不伪造状态、不关闭页面。
  Future<void> _toggleDesktopFullscreen() async {
    final bindings = _bindings;
    if (bindings is! DesktopVideoPlayerBindings) return;
    final result = await bindings.fullscreen.toggle();
    if (!result.succeeded) {
      _playback.showOperationFailure('无法切换全屏');
    }
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
    // 帮助文本由平台 bindings 决定：Android 描述触摸手势（单击/双击 15 秒/
    // 长按/横拖），Windows 描述桌面交互（单击播放、双击全屏、5 秒方向键、
    // 右方向键长按 3 倍速、音量与静音、Escape）。保持单一 hint 结构与既有
    // a11y 契约一致。
    final hint = switch (_bindings) {
      MobileVideoPlayerBindings() =>
        controlsVisible
            ? '激活以隐藏播放控件；单击切换控制栏，双击快退或快进 15 秒，长按 3 倍速，左右拖动快进快退'
            : '激活以显示播放控件；单击切换控制栏，双击快退或快进 15 秒，长按 3 倍速，左右拖动快进快退',
      DesktopVideoPlayerBindings() =>
        controlsVisible
            ? '激活以播放或暂停；双击或 F 切换全屏，左右方向键快退或快进 5 秒，右方向键长按临时 3 倍速，上下方向键调整音量，M 静音，Escape 退出全屏或关闭'
            : '激活以播放或暂停；双击或 F 切换全屏，左右方向键快退或快进 5 秒，右方向键长按临时 3 倍速，上下方向键调整音量，M 静音，Escape 退出全屏或关闭',
    };

    return Semantics(
      label: '视频播放器：${widget.fileName}',
      value: valueText,
      hint: hint,
      button: true,
      enabled: true,
      onTap: _handleSurfaceSemanticsTap,
      child: Focus(
        focusNode: _playerFocusNode,
        onKeyEvent: _handleSurfaceKeyEvent,
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

  /// 语义 tap 的等价键盘操作：Mobile 切换控制栏，Desktop 播放/暂停。
  void _handleSurfaceSemanticsTap() {
    final mobile = _mobile;
    if (mobile != null) {
      mobile.handleTap();
      return;
    }
    _playback.togglePlayPause();
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
    final desktop = _desktop;
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
                      onBack: () => unawaited(_requestClose()),
                      onSpeedChanged: _playback.setPersistentSpeed,
                      onVolumeChanged: _playback.setVolume,
                      onPointerEnter: desktop?.onControlsPointerEnter,
                      onPointerExit: desktop?.onControlsPointerExit,
                      onFocusChanged: desktop == null
                          ? null
                          : _handleDesktopControlsFocusChanged,
                      onInteractionStarted: _handleControlsInteractionStarted,
                      onInteractionEnded: _handleControlsInteractionEnded,
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
    final desktop = _desktop;
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
                        onPointerEnter: desktop?.onControlsPointerEnter,
                        onPointerExit: desktop?.onControlsPointerExit,
                        onFocusChanged: desktop == null
                            ? null
                            : _handleDesktopControlsFocusChanged,
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
