import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 缩略图缓存管理器。
///
/// 缓存目录: `{应用 Support 目录}/.cache/thumbnails/`
/// 缓存 Key: `MD5(relativePath|fileSize|lastModified)` → `.jpg`
///
/// 首次访问时自动创建缓存目录。
class MediaThumbnailCache {
  final Directory _cacheDir;

  /// 使用默认缓存路径（应用 Support 目录下的 `.cache/thumbnails/`）。
  ///
  /// 与数据库和日志同在一个父目录，确保有写入权限。
  static Future<MediaThumbnailCache> defaultLocation() async {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/.cache/thumbnails');
    return MediaThumbnailCache._(cacheDir);
  }

  /// 使用自定义缓存目录（主要用于测试）。
  MediaThumbnailCache.custom(Directory cacheDir) : _cacheDir = cacheDir;

  MediaThumbnailCache._(this._cacheDir);

  /// 缓存目录路径。
  Directory get cacheDir => _cacheDir;

  /// 计算缓存 Key。
  ///
  /// 格式: `MD5(relativePath|fileSize|lastModified)`
  static String computeKey(String relativePath, int fileSize, int lastModified) {
    final input = '$relativePath|$fileSize|$lastModified';
    return md5.convert(utf8.encode(input)).toString();
  }

  /// 获取已缓存的缩略图文件，不存在时返回 null。
  File? get(String relativePath, int fileSize, int lastModified) {
    final key = computeKey(relativePath, fileSize, lastModified);
    final file = File('${_cacheDir.path}${Platform.pathSeparator}$key.jpg');
    return file.existsSync() ? file : null;
  }

  /// 写入缩略图到缓存。
  ///
  /// 若目录不存在则自动创建。
  Future<File> put(String relativePath, int fileSize, int lastModified, List<int> jpegBytes) async {
    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
    }
    final key = computeKey(relativePath, fileSize, lastModified);
    final file = File('${_cacheDir.path}${Platform.pathSeparator}$key.jpg');
    await file.writeAsBytes(jpegBytes, flush: true);
    return file;
  }
}
