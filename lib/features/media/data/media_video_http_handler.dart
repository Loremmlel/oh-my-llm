import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';
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
class MediaVideoHttpHandler implements HttpRouteHandler {
  final MediaDirectoryScanner _scanner;

  MediaVideoHttpHandler({required MediaDirectoryScanner scanner})
      : _scanner = scanner;

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' &&
      request.uri.path.startsWith('/api/media/video/');

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      // 提取相对路径：/api/media/video/sister/cat.mp4 → /sister/cat.mp4
      final rawPath = request.uri.path.substring('/api/media/video'.length);
      if (rawPath.isEmpty || rawPath == '/') {
        writeJsonError(request.response, HttpStatus.badRequest, '缺少文件路径');
        return;
      }
      // request.uri.path 保留了 percent-encoding，必须解码以支持中文路径
      final relativePath = Uri.decodeComponent(rawPath);

      // 安全校验
      final resolvedPath = _scanner.resolvePath(relativePath);

      final file = File(resolvedPath);
      if (!file.existsSync()) {
        writeJsonError(request.response, HttpStatus.notFound, '文件不存在');
        return;
      }

      final fileSize = file.lengthSync();
      final mimeType = mimeTypeFromExtension(relativePath);

      // 解析 Range 头
      final rangeHeader = request.headers['range']?.single;
      final range = rangeHeader != null ? _parseRange(rangeHeader, fileSize) : null;

      if (rangeHeader != null && range == null) {
        // Range 头存在但解析失败 → 416
        _writeRangeNotSatisfiable(request.response, fileSize);
        return;
      }

      if (range != null) {
        // ── 206 Partial Content ──
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
        // ── 200 OK（完整文件）──
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

    // 不支持多 Range
    if (rangesPart.contains(',')) return null;

    try {
      final dashIdx = rangesPart.indexOf('-');
      if (dashIdx < 0) return null;

      final startStr = rangesPart.substring(0, dashIdx).trim();
      final endStr = rangesPart.substring(dashIdx + 1).trim();

      int start;
      int end;

      if (startStr.isEmpty && endStr.isEmpty) {
        return null; // 格式错误
      } else if (startStr.isEmpty) {
        // bytes=-<suffix>
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
          // bytes=<start>-
          end = fileSize - 1;
        }
      }

      // 修正 end 越界
      if (end >= fileSize) end = fileSize - 1;

      // 无效范围
      if (start >= fileSize || start > end) return null;

      return _ParsedRange(start, end);
    } on FormatException {
      return null; // 非数字值 → 无效
    }
  }

  /// 写入 416 Range Not Satisfiable 响应。
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
