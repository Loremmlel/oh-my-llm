import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../widgets/video_player_controls.dart';
import 'video_player_gesture.dart';
import 'video_player_state.dart';

/// 全屏视频播放器。
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

  @override
  void initState() {
    super.initState();
    _gesture.onStateChanged = () => setState(() {});
    _gesture.onBackPressed = () => Navigator.pop(context);
    _gesture.setMounted(true);

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
    _gesture.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
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
      body: GestureDetector(
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
            Center(child: _buildBody(s)),
            VideoCenterHint(
              visible: s.isInitialized &&
                  !s.hasError &&
                  (!s.isPlaying || s.centerHint != CenterHintType.none),
              hintType: s.centerHint,
              seekPosition: s.seekPreviewPosition,
              showPauseIcon: s.isInitialized && !s.hasError && !s.isPlaying,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
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
                        onInteractionStarted: () =>
                            s.hideTimer?.cancel(),
                        onInteractionEnded: _gesture.resetHideTimer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
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
                        dragPosition:
                            Duration(milliseconds: s.dragPositionMs.round()),
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
          ],
        ),
      ),
    );
  }

  Widget _buildBody(VideoPlayerUiState s) {
    if (s.hasError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 64),
          const SizedBox(height: 12),
          Text(
            s.errorMessage ?? '视频加载失败',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
            textAlign: TextAlign.center,
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
      );
    }

    if (!s.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final ctrl = s.controller;
    if (ctrl == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: VideoPlayer(ctrl),
    );
  }
}
