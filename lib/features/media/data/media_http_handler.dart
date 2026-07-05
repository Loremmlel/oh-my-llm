import 'dart:convert';
import 'dart:io';

import 'media_http_handler_base.dart';

/// 处理 `GET /api/media/list` 及 `GET /api/media/list/*` 请求的 Handler。
class MediaHttpHandler extends MediaHttpHandlerBase {
  MediaHttpHandler({required super.scanner})
      : super(urlPrefix: '/api/media/list');

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      (request.uri.path == urlPrefix ||
          request.uri.path.startsWith('$urlPrefix/'));

  @override
  Future<void> handleSafe(HttpRequest request, String relativePath) async {
    final items = await scanner.scan(relativePath);

    final json = const JsonEncoder.withIndent(null)
        .convert(items.map((i) => i.toJson()).toList());
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write(json)
      ..close();
  }
}
