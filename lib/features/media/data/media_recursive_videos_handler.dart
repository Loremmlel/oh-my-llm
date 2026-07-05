import 'dart:convert';
import 'dart:io';

import 'media_http_handler_base.dart';

/// 处理 `GET /api/media/videos/recursive` 及 `GET /api/media/videos/recursive/*` 请求的 Handler。
class MediaRecursiveVideosHandler extends MediaHttpHandlerBase {
  MediaRecursiveVideosHandler({required super.scanner})
      : super(urlPrefix: '/api/media/videos/recursive');

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      (request.uri.path == urlPrefix ||
          request.uri.path.startsWith('$urlPrefix/'));

  @override
  Future<void> handleSafe(HttpRequest request, String relativePath) async {
    final videos = await scanner.scanRecursiveVideos(relativePath);

    final json = const JsonEncoder.withIndent(null)
        .convert(videos.map((v) => v.toJson()).toList());
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write(json)
      ..close();
  }
}
