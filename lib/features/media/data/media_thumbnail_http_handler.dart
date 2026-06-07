import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';
import 'media_thumbnail_cache.dart';
import 'media_thumbnail_generator.dart';

/// 处理 `GET /api/media/thumbnail/{path}` 请求的 Handler。
///
/// 流程：路径校验 → 查缓存 → 缓存未命中则生成 → 写缓存 → 返回 JPEG。
///
/// 缩略图是派生数据（可从原文件重新生成），因此设置 `Cache-Control: public, max-age=86400`
/// 允许客户端缓存。原始媒体文件 handler 不设置此头以保持安全约束。
class MediaThumbnailHttpHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;
  final MediaThumbnailGenerator _generator;
  final MediaThumbnailCache _cache;

  MediaThumbnailHttpHandler({
    required MediaDirectoryScanner scanner,
    required MediaThumbnailGenerator generator,
    required MediaThumbnailCache cache,
  })  : _scanner = scanner,
        _generator = generator,
        _cache = cache;

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      request.uri.path.startsWith('/api/media/thumbnail/');

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      // 提取相对路径
      final rawPath =
          request.uri.path.substring('/api/media/thumbnail'.length);
      if (rawPath.isEmpty || rawPath == '/') {
        writeJsonError(request.response, HttpStatus.badRequest, '缺少文件路径');
        return;
      }
      final relativePath = Uri.decodeComponent(rawPath);

      // 安全校验
      final resolvedPath = _scanner.resolvePath(relativePath);

      // 检查文件存在性（单次 stat 调用，fileSize 后续复用）
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        writeJsonError(request.response, HttpStatus.notFound, '文件不存在');
        return;
      }

      final stat = file.statSync();
      final fileSize = stat.size;
      final lastModified = stat.modified.millisecondsSinceEpoch;

      // — 缓存命中 —
      final cached = _cache.get(relativePath, fileSize, lastModified);
      if (cached != null) {
        // 从缓存文件读取字节，避免流式传输中文件锁问题
        final cachedBytes = await cached.readAsBytes();
        await _sendJpegResponse(request.response, cachedBytes, cachedBytes.length);
        return;
      }

      // — 生成缩略图 —
      final jpegBytes = await _generator.generate(relativePath);

      // — 返回 —
      await _sendJpegResponse(request.response, jpegBytes, jpegBytes.length);

      // — 写入缓存（响应已发送，缓存失败不影响客户端） —
      try {
        await _cache.put(relativePath, fileSize, lastModified, jpegBytes);
      } catch (_) {
        // 缓存写入失败不阻塞——客户端已收到缩略图
      }
    } on PathTraversalException catch (e) {
      writeJsonError(
          request.response, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on ProcessException catch (e) {
      // ffmpeg/ffprobe 未安装或无法启动
      writeJsonError(
          request.response, HttpStatus.internalServerError, '外部工具调用失败（ffmpeg 可能未安装）: ${e.message}');
    } on ThumbnailException catch (e) {
      writeJsonError(
          request.response, HttpStatus.internalServerError, '缩略图生成失败: ${e.message}');
    } on FileSystemException catch (e) {
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      writeJsonError(request.response, status, '文件访问失败: ${e.message}');
    } catch (e) {
      writeJsonError(
          request.response, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }

  /// 发送 JPEG 响应（从内存字节数组）。
  ///
  /// 直接从内存写入，避免流式传输中的文件锁问题。
  Future<void> _sendJpegResponse(HttpResponse response, List<int> bytes, int contentLength) async {
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'jpeg')
      ..headers.set('Content-Length', contentLength.toString())
      // 缩略图是派生缓存数据，允许客户端缓存 24 小时
      ..headers.set('Cache-Control', 'public, max-age=86400')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..add(bytes);
    await response.close();
  }
}
