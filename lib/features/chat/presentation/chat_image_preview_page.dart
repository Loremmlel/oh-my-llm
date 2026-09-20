import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'widgets/images/chat_image_strip.dart';

class ChatImagePreviewPage extends StatefulWidget {
  const ChatImagePreviewPage({super.key, required this.imageId});
  final String imageId;
  @override
  State<ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState extends State<ChatImagePreviewPage> {
  final _transform = TransformationController();
  void _close() => context.canPop() ? context.pop() : context.go('/chat');
  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      8.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: Scaffold(
      appBar: AppBar(
        title: const Text('图片预览'),
        leading: IconButton(
          autofocus: true,
          onPressed: _close,
          tooltip: '关闭图片',
          icon: const Icon(Icons.close),
        ),
        actions: [
          IconButton(
            onPressed: () => _zoom(0.5),
            tooltip: '缩小图片',
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            onPressed: () => _transform.value = Matrix4.identity(),
            tooltip: '恢复图片大小',
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            onPressed: () => _zoom(2),
            tooltip: '放大图片',
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
      body: SafeArea(
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 8,
          child: Center(child: ChatImageContent(id: widget.imageId)),
        ),
      ),
    ),
  );
}
