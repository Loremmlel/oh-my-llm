import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';

import 'media_http_handler_base.dart';
import 'media_thumbnail_cache.dart';
import 'media_thumbnail_generator.dart';

/// 处理 `GET /api/media/thumbnail/{path}` 请求的 Handler。
///
/// 流程：路径校验 → 查缓存 → 缓存未命中则生成 → 写缓存 → 返回 JPEG。
class MediaThumbnailHttpHandler extends MediaHttpHandlerBase {
  final MediaThumbnailGenerator _generator;
  final MediaThumbnailCache _cache;

  MediaThumbnailHttpHandler({
    required super.scanner,
    required MediaThumbnailGenerator generator,
    required MediaThumbnailCache cache,
  })  : _generator = generator,
        _cache = cache,
        super(urlPrefix: '/api/media/thumbnail/');

  @override
  Future<void> handleSafe(HttpRequest request, String relativePath) async {
    if (relativePath == '/') {
      writeJsonError(request.response, HttpStatus.badRequest, '缺少文件路径');
      return;
    }

    final resolvedPath = scanner.resolvePath(relativePath);
    final file = File(resolvedPath);
    if (!file.existsSync()) {
      writeJsonError(request.response, HttpStatus.notFound, '文件不存在');
      return;
    }

    final stat = file.statSync();
    final fileSize = stat.size;
    final lastModified = stat.modified.millisecondsSinceEpoch;

    final cached = _cache.get(relativePath, fileSize, lastModified);
    if (cached != null) {
      final cachedBytes = await cached.readAsBytes();
      await _sendJpegResponse(request.response, cachedBytes, cachedBytes.length);
      return;
    }

    final jpegBytes = await _generator.generate(relativePath);
    await _sendJpegResponse(request.response, jpegBytes, jpegBytes.length);

    try {
      await _cache.put(relativePath, fileSize, lastModified, jpegBytes);
    } catch (_) {
      // 缓存写入失败不阻塞
    }
  }

  @override
  Future<bool> onUnhandledError(HttpRequest request, Object error) async {
    if (error is ProcessException) {
      writeJsonError(
        request.response,
        HttpStatus.internalServerError,
        '外部工具调用失败（ffmpeg 可能未安装）: ${error.message}',
      );
      return true;
    }
    if (error is ThumbnailException) {
      writeJsonError(
        request.response,
        HttpStatus.internalServerError,
        '缩略图生成失败: ${error.message}',
      );
      return true;
    }
    return false;
  }

  Future<void> _sendJpegResponse(HttpResponse response, List<int> bytes, int contentLength) async {
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'jpeg')
      ..headers.set('Content-Length', contentLength.toString())
      ..headers.set('Cache-Control', 'public, max-age=86400')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..add(bytes);
    await response.close();
  }
}
