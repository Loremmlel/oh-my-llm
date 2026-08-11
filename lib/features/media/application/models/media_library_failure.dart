/// 媒体库操作失败的用户面向抽象，不暴露底层文件系统/HTTP 具体原因。
library;

enum MediaLibraryFailureCode {
  sourceUnavailable,
  invalidPath,
  notFound,
  accessDenied,
  networkUnavailable,
  timeout,
  invalidResponse,
  unsupportedMedia,
  thumbnailUnavailable,
}

final class MediaLibraryFailure implements Exception {
  const MediaLibraryFailure(this.code, this.message);
  final MediaLibraryFailureCode code;
  final String message;
  @override
  String toString() => message;
}
