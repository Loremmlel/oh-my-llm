import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';

import 'media_http_handler_base.dart';
import 'media_mime_types.dart';

/// Range 请求解析结果。
class _ParsedRange {
  final int start;
  final int end; // inclusive
  const _ParsedRange(this.start, this.end);

  @override
  String toString() => '$start-$end';
}

/// 处理 `GET /api/media/video/{path}` 请求的 Handler。
///
/// 支持 HTTP Range 请求，正确返回 206 Partial Content。
/// 使用流式传输避免阻塞事件循环。
class MediaVideoHttpHandler extends MediaHttpHandlerBase {
  MediaVideoHttpHandler({required super.scanner})
      : super(urlPrefix: '/api/media/video/');

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

    final fileSize = file.lengthSync();
    final mimeType = mimeTypeFromExtension(relativePath);

    final rangeHeader = request.headers['range']?.single;
    final range = rangeHeader != null ? _parseRange(rangeHeader, fileSize) : null;

    if (rangeHeader != null && range == null) {
      _writeRangeNotSatisfiable(request.response, fileSize);
      return;
    }

    if (range != null) {
      final length = range.end - range.start + 1;
      final stream = file.openRead(range.start, range.end + 1);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType.parse(mimeType)
        ..headers.set('Content-Range', 'bytes ${range.start}-${range.end}/$fileSize')
        ..headers.set('Content-Length', length.toString())
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(stream);
      await request.response.close();
    } else {
      final stream = file.openRead();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(mimeType)
        ..headers.set('Content-Length', fileSize.toString())
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Access-Control-Allow-Origin', '*');
      await request.response.addStream(stream);
      await request.response.close();
    }
  }

  /// 解析 Range 请求头，返回解析后的范围或 null（表示解析失败）。
  ///
  /// 支持格式：
  /// - `bytes=<start>-<end>` 闭区间
  /// - `bytes=<start>-` 从 start 到 EOF
  /// - `bytes=-<suffix>` 最后 suffix 字节
  ///
  /// 不支持多 Range（`bytes=0-100, 200-300`），返回 null。
  /// 无效值（start >= fileSize 或 start > end）返回 null。
  _ParsedRange? _parseRange(String header, int fileSize) {
    if (!header.startsWith('bytes=')) return null;

    final rangesPart = header.substring('bytes='.length).trim();
    if (rangesPart.isEmpty) return null;
    if (rangesPart.contains(',')) return null;

    try {
      final dashIdx = rangesPart.indexOf('-');
      if (dashIdx < 0) return null;

      final startStr = rangesPart.substring(0, dashIdx).trim();
      final endStr = rangesPart.substring(dashIdx + 1).trim();

      int start;
      int end;

      if (startStr.isEmpty && endStr.isEmpty) {
        return null;
      } else if (startStr.isEmpty) {
        final suffix = int.parse(endStr);
        if (suffix <= 0) return null;
        start = (fileSize - suffix).clamp(0, fileSize - 1);
        end = fileSize - 1;
      } else {
        start = int.parse(startStr);
        if (start < 0) return null;
        if (endStr.isNotEmpty) {
          end = int.parse(endStr);
        } else {
          end = fileSize - 1;
        }
      }

      if (end >= fileSize) end = fileSize - 1;
      if (start >= fileSize || start > end) return null;

      return _ParsedRange(start, end);
    } on FormatException {
      return null;
    }
  }

  void _writeRangeNotSatisfiable(HttpResponse response, int fileSize) {
    response
      ..statusCode = HttpStatus.requestedRangeNotSatisfiable
      ..headers.contentType = ContentType.json
      ..headers.set('Content-Range', 'bytes */$fileSize')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write('{"error":"请求的 Range 无法满足"}')
      ..close();
  }
}
