import 'dart:io';

import '../../application/models/media_library_failure.dart';
import '../../application/models/media_resource.dart';
import '../../application/models/media_resource_request.dart';
import '../../application/ports/media_library.dart';
import '../../domain/media_file_classification.dart';
import '../../domain/models/file_item.dart';
import '../scanning/media_directory_scanner.dart';
import '../scanning/media_thumbnail_cache.dart';
import '../scanning/media_thumbnail_generator.dart';

/// 直接访问本地文件系统的媒体库实现（Windows 本地浏览专用）。
///
/// 无任何 HTTP / peer 依赖：路径全部经 [MediaDirectoryScanner] 解析并做
/// 穿越防护，资源 URI 一律由 `File.absolute.uri` 构造，不手拼 `file:///`。
/// 文件系统异常经 [_mapFileSystem] 映射为固定的 [MediaLibraryFailure]，
/// 绝不把 `exception.path` 插进用户可见消息。
final class LocalMediaLibrary implements MediaLibrary {
  LocalMediaLibrary({
    required this._scanner,
    required this._cache,
    required this._generator,
  });

  final MediaDirectoryScanner _scanner;
  final MediaThumbnailCache _cache;
  final MediaThumbnailGenerator _generator;

  @override
  Future<List<FileItem>> listDirectory(String relativePath) =>
      _mapFileSystem(() => _scanner.scan(relativePath), rootOperation: true);

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) =>
      _mapFileSystem(
        () => _scanner.scanRecursiveVideos(relativePath),
        rootOperation: true,
      );

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) async {
    if (!request.hasThumbnail) return null;
    // 缓存读取不抛异常（existsSync 语义），故无需经 _mapFileSystem 映射
    final hit = _cache.get(
      request.relativePath,
      request.sizeBytes,
      request.lastModified,
    );
    if (hit != null) return LocalMediaResource(hit.absolute.uri);
    try {
      final bytes = await _generator.generate(request.relativePath);
      final file = await _cache.put(
        request.relativePath,
        request.sizeBytes,
        request.lastModified,
        bytes,
      );
      return LocalMediaResource(file.absolute.uri);
    } on ThumbnailException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.thumbnailUnavailable,
        '缩略图不可用',
      );
    } on FileSystemException catch (e) {
      throw _mapFileSystemError(e, rootOperation: false);
    }
  }

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) async {
    final supported = switch (request.kind) {
      MediaAssetKind.image => isImageFile(request.relativePath),
      MediaAssetKind.video => isVideoFile(request.relativePath),
    };
    if (!supported) {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.unsupportedMedia,
        '不支持的媒体类型',
      );
    }
    return _mapFileSystem(() async {
      final resolvedPath = _scanner.resolvePath(request.relativePath);
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        // 显式携带 Win32 ERROR_FILE_NOT_FOUND，确保缺失资产经统一映射为 notFound
        throw FileSystemException(
          '文件不存在',
          resolvedPath,
          const OSError('文件不存在', 2),
        );
      }
      return LocalMediaResource(file.absolute.uri);
    }, rootOperation: false);
  }

  /// 统一映射文件系统操作异常为固定的 [MediaLibraryFailure]。
  ///
  /// 分支确定：路径穿越→invalidPath；errorCode 2/3 在根/列表操作→
  /// sourceUnavailable、在资产操作→notFound；errorCode 5/13→accessDenied；
  /// 其余 FileSystemException→sourceUnavailable（固定安全消息）。
  /// 所有消息均为常量，永不把 `exception.path` 插入用户可见文本。
  Future<T> _mapFileSystem<T>(
    Future<T> Function() operation, {
    required bool rootOperation,
  }) async {
    try {
      return await operation();
    } on PathTraversalException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidPath,
        '媒体路径无效',
      );
    } on FileSystemException catch (e) {
      throw _mapFileSystemError(e, rootOperation: rootOperation);
    }
  }

  Never _mapFileSystemError(
    FileSystemException exception, {
    required bool rootOperation,
  }) {
    final errorCode = exception.osError?.errorCode;
    if (errorCode == 2 || errorCode == 3) {
      if (rootOperation) {
        throw const MediaLibraryFailure(
          MediaLibraryFailureCode.sourceUnavailable,
          '媒体根目录不可用',
        );
      }
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.notFound,
        '媒体资源不存在',
      );
    }
    if (errorCode == 5 || errorCode == 13) {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.accessDenied,
        '没有媒体访问权限',
      );
    }
    throw const MediaLibraryFailure(
      MediaLibraryFailureCode.sourceUnavailable,
      '媒体根目录不可用',
    );
  }
}
