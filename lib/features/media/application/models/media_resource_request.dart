/// 媒体资源请求值：资产或缩略图，携带缓存失效所需全部键。
library;

import 'package:equatable/equatable.dart';

enum MediaAssetKind { image, video }

sealed class MediaResourceRequest extends Equatable {
  const MediaResourceRequest();
}

final class MediaAssetRequest extends MediaResourceRequest {
  const MediaAssetRequest({required this.kind, required this.relativePath});
  final MediaAssetKind kind;
  final String relativePath;
  @override
  List<Object?> get props => [kind, relativePath];
}

final class MediaThumbnailRequest extends MediaResourceRequest {
  const MediaThumbnailRequest({
    required this.relativePath,
    required this.sizeBytes,
    required this.lastModified,
    required this.hasThumbnail,
  });
  final String relativePath;
  final int sizeBytes;
  final int lastModified;
  final bool hasThumbnail;
  @override
  List<Object?> get props => [
    relativePath,
    sizeBytes,
    lastModified,
    hasThumbnail,
  ];
}
