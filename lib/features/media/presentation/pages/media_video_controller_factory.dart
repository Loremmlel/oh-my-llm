import 'dart:io';

import 'package:video_player/video_player.dart';

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';

/// 播放器控制器工厂：按 [MediaResource] 选择本地文件或网络数据源。
///
/// 这是 [MediaResource] → [VideoPlayerController] 的窄适配层，
/// 不引入完整的播放器引擎抽象；初始化由播放页面负责。
typedef MediaVideoControllerFactory = VideoPlayerController Function(
  MediaResource resource,
);

VideoPlayerController createMediaVideoController(MediaResource resource) =>
    switch (resource) {
      LocalMediaResource(:final uri) => VideoPlayerController.file(
        File.fromUri(uri),
      ),
      NetworkMediaResource(:final uri, :final headers) =>
        VideoPlayerController.networkUrl(uri, httpHeaders: headers),
    };
