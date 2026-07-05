import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';

import 'media_http_handler_base.dart';
import 'media_mime_types.dart';

/// 处理 `GET /api/media/image/{path}` 请求的 Handler。
///
/// 返回原始图片文件，使用流式传输避免大文件 OOM。
class MediaImageHttpHandler extends MediaHttpHandlerBase {
  MediaImageHttpHandler({required super.scanner})
      : super(urlPrefix: '/api/media/image/');

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

    final contentLength = file.lengthSync();
    final mimeType = mimeTypeFromExtension(relativePath);

    final stream = file.openRead();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.parse(mimeType)
      ..headers.set('Content-Length', contentLength.toString())
      ..headers.set('Accept-Ranges', 'bytes')
      ..headers.set('Access-Control-Allow-Origin', '*');

    await request.response.addStream(stream);
    await request.response.close();
  }
}
