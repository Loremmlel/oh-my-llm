import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏图片查看器。
///
/// 从服务端加载单张图片，黑色背景，左上角返回按钮。
/// Phase 2 仅显示单张图片，不支持切换、缩放和手势。
class ImageViewerPage extends StatefulWidget {
  final String imageUrl;
  final String fileName;

  const ImageViewerPage({
    super.key,
    required this.imageUrl,
    required this.fileName,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  @override
  void initState() {
    super.initState();
    // 沉浸式全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 恢复系统 UI 模式
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 全屏图片 ──
          Center(
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                final total = loadingProgress.expectedTotalBytes;
                final progress = total != null
                    ? loadingProgress.cumulativeBytesLoaded / total
                    : null;
                return Center(
                  child: CircularProgressIndicator(
                    value: progress,
                    color: Colors.white54,
                  ),
                );
              },
              errorBuilder: (context, error, stack) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 64),
                      SizedBox(height: 12),
                      Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // ── 左上角返回按钮 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
