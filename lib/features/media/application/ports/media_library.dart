/// 媒体库访问端口：面向调用方的传输中立契约。
library;

import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

abstract interface class MediaLibrary {
  Future<List<FileItem>> listDirectory(String relativePath);
  Future<List<VideoItem>> listVideosRecursively(String relativePath);
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request);
  Future<MediaResource> resolveAsset(MediaAssetRequest request);
}
