import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 全屏视频播放器。
///
/// 使用 video_player 播放服务端视频（支持 HTTP Range）。
/// Phase 2 仅提供基本播放/暂停功能，不含自定义控制层。
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String fileName;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    required this.fileName,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // 先清理旧 controller，避免重试时泄漏资源
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      _controller = controller;
      controller.addListener(_onControllerUpdate);

      await controller.initialize();
      if (!mounted) return;
      controller.play();
      setState(() => _isInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = '视频加载失败: $e';
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 视频画面 ──
          Center(
            child: _buildBody(),
          ),
          // ── 暂停时中央播放图标 ──
          if (_isInitialized && !_hasError && _controller != null)
            if (!_controller!.value.isPlaying)
              const Center(
                child: Icon(Icons.play_arrow, color: Colors.white54, size: 80),
              ),
          // ── 左上角返回按钮 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                _controller?.removeListener(_onControllerUpdate);
                _controller?.dispose();
                Navigator.pop(context);
              },
            ),
          ),
          // ── 底部播放/暂停按钮 ──
          if (_isInitialized && !_hasError)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    (_controller?.value.isPlaying ?? false)
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
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

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}
