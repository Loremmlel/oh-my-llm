import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';
import 'media_mime_types.dart';

/// 处理 `GET /api/media/image/{path}` 请求的 Handler。
///
/// 返回原始图片文件，使用流式传输避免大文件 OOM。
class MediaImageHttpHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;

  MediaImageHttpHandler({required MediaDirectoryScanner scanner})
      : _scanner = scanner;

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      request.uri.path.startsWith('/api/media/image/');

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      // 提取相对路径：/api/media/image/sister/photo.jpg → /sister/photo.jpg
      final rawPath = request.uri.path.substring('/api/media/image'.length);
      if (rawPath.isEmpty || rawPath == '/') {
        writeJsonError(request.response, HttpStatus.badRequest, '缺少文件路径');
        return;
      }
      // request.uri.path 保留了 percent-encoding，必须解码以支持中文路径
      final relativePath = Uri.decodeComponent(rawPath);

      // 安全校验
      final resolvedPath = _scanner.resolvePath(relativePath);

      // 检查文件存在性
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        writeJsonError(request.response, HttpStatus.notFound, '文件不存在');
        return;
      }

      final contentLength = file.lengthSync();
      final mimeType = mimeTypeFromExtension(relativePath);

      // 流式传输文件内容，避免大图片 OOM
      final stream = file.openRead();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(mimeType)
        ..headers.set('Content-Length', contentLength.toString())
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Access-Control-Allow-Origin', '*');

      // 流式传输（TOCTOU 风险：validate 之后文件可能被删除，
      // 若 addStream 失败则 TCP 连接自动关闭，客户端自行处理）
      await request.response.addStream(stream);
      await request.response.close();
    } on PathTraversalException catch (e) {
      writeJsonError(request.response, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on FileSystemException catch (e) {
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      writeJsonError(request.response, status, '文件访问失败: ${e.message}');
    } catch (e) {
      writeJsonError(request.response, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }
}
