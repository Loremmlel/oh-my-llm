import 'dart:convert';
import 'dart:io';

import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';

/// 处理 `GET /api/media/list` 及 `GET /api/media/list/*` 请求的 Handler。
///
/// 与 [SyncHttpHandler] 平等，都实现 [HttpRouteHandler] 接口，
/// 挂载到同一个 [SyncHttpServer] 路由器上。
class MediaHttpHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;

  MediaHttpHandler({required String rootDirectory})
      : _scanner = MediaDirectoryScanner(rootDirectory);

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      (request.uri.path == '/api/media/list' ||
          request.uri.path.startsWith('/api/media/list/'));

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      // 提取路径：/api/media/list/... → relativePath
      // /api/media/list → /
      // /api/media/list/ → /
      // /api/media/list/sister/video → /sister/video
      final rawPath = request.uri.path == '/api/media/list'
          ? ''
          : request.uri.path.substring('/api/media/list'.length);
      final relativePath = rawPath.isEmpty || rawPath == '/'
          ? '/'
          : Uri.decodeComponent(rawPath);

      final items = await _scanner.scan(relativePath);

      final json = const JsonEncoder.withIndent(null)
          .convert(items.map((i) => i.toJson()).toList());
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write(json)
        ..close();
    } on PathTraversalException catch (e) {
      _writeError(request, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on FileSystemException catch (e) {
      // errno 2 = ENOENT (No such file or directory)
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      _writeError(request, status, '目录访问失败: ${e.message}');
    } catch (e) {
      _writeError(request, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }

  void _writeError(HttpRequest request, int status, String message) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write(jsonEncode({'error': message}))
      ..close();
  }
}
