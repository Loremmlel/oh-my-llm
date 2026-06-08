import 'dart:convert';
import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';

/// 处理 `GET /api/media/videos/recursive` 及 `GET /api/media/videos/recursive/*` 请求的 Handler。
///
/// 递归扫描指定目录树下所有视频文件，返回扁平 JSON 列表。
class MediaRecursiveVideosHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;

  MediaRecursiveVideosHandler({required MediaDirectoryScanner scanner})
      : _scanner = scanner;

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      (request.uri.path == '/api/media/videos/recursive' ||
          request.uri.path.startsWith('/api/media/videos/recursive/'));

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      final rawPath = request.uri.path == '/api/media/videos/recursive'
          ? ''
          : request.uri.path.substring('/api/media/videos/recursive'.length);
      final relativePath = rawPath.isEmpty || rawPath == '/'
          ? '/'
          : Uri.decodeComponent(rawPath);

      final videos = await _scanner.scanRecursiveVideos(relativePath);

      final json = const JsonEncoder.withIndent(null)
          .convert(videos.map((v) => v.toJson()).toList());
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write(json)
        ..close();
    } on PathTraversalException catch (e) {
      writeJsonError(
          request.response, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on FileSystemException catch (e) {
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      writeJsonError(request.response, status, '目录访问失败: ${e.message}');
    } catch (e) {
      writeJsonError(
          request.response, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }
}
