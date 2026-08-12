import 'dart:io';

import 'package:flutter/material.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';

/// 按 [MediaResource] 渲染图片：本地文件走 [Image.file]，远端走 [Image.network]。
///
/// 加载中/失败的可选呈现由调用方通过 [loading] 与 [errorBuilder] 注入；
/// 未注入时加载态显示细进度条，失败态交给 Image 默认行为。
/// 本地文件不在本组件内做 IO 预检，解码失败由 errorBuilder 呈现。
class MediaImageResourceView extends StatelessWidget {
  const MediaImageResourceView({
    super.key,
    required this.resource,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
    this.loading,
  });

  final MediaResource resource;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// 加载中占位；未提供时使用细进度条。
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return switch (resource) {
      LocalMediaResource(:final uri) => Image.file(
        File.fromUri(uri),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
        frameBuilder: _frameBuilder,
      ),
      NetworkMediaResource(:final uri, :final headers) => Image.network(
        uri.toString(),
        headers: headers,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
        loadingBuilder: _loadingBuilder,
      ),
    };
  }

  /// 共享的加载占位：两个 builder 都复用调用方注入的 [loading]。
  Widget _loading(BuildContext context) =>
      loading ?? const Center(child: CircularProgressIndicator(strokeWidth: 2));

  /// 本地文件逐帧加载：首帧未就绪前显示占位，已同步加载/有帧后直出子节点。
  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) => wasSynchronouslyLoaded || frame != null ? child : _loading(context);

  /// 网络图按进度回调：进度为 null（未开始）时显示占位，有进度后直出子节点。
  Widget _loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? progress,
  ) => progress == null ? child : _loading(context);
}
