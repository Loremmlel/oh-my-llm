import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_cache.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_generator.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';

/// 使用 image 包生成一个有效的 PNG 图片字节数组。
List<int> _generatePng() {
  final image = img.Image(width: 1, height: 1);
  image.setPixelRgba(0, 0, 255, 0, 0, 255); // 红色
  return img.encodePng(image);
}

/// 启动集成测试 HTTP 服务器，返回 (server, port)。
Future<({SyncHttpServer server, int port})> _startTestServer({
  required MediaDirectoryScanner scanner,
  required MediaThumbnailHttpHandler handler,
}) async {
  final server = SyncHttpServer();
  final port = await server.start(handlers: [handler]);
  return (server: server, port: port);
}

void main() {
  group('MediaThumbnailHttpHandler 集成测试', () {
    late Directory tempDir;
    late Directory cacheTempDir; // 缓存独立目录，避免 Windows 文件锁导致 tearDown 失败
    late MediaDirectoryScanner scanner;
    late MediaThumbnailCache cache;
    late MediaThumbnailGenerator generator;
    late MediaThumbnailHttpHandler handler;
    late List<int> validPng;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('thumbnail_http_test_');
      cacheTempDir = Directory.systemTemp.createTempSync(
        'thumbnail_http_cache_',
      );
      scanner = MediaDirectoryScanner(tempDir.path);
      cache = MediaThumbnailCache.custom(
        Directory('${cacheTempDir.path}/.cache/thumbnails'),
      );
      generator = MediaThumbnailGenerator(scanner: scanner);
      handler = MediaThumbnailHttpHandler(
        scanner: scanner,
        generator: generator,
        cache: cache,
      );
      validPng = _generatePng();
    });

    tearDown(() {
      // try-catch 防御 Windows 文件锁：缓存文件可能尚未被 OS 释放
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        cacheTempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    group('handle — 图片缩略图', () {
      test('首次生成与缓存命中返回一致的 JPEG 数据', () async {
        final imgFile = File('${tempDir.path}/photo.png');
        await imgFile.writeAsBytes(validPng);

        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
          final url = Uri.parse(
            'http://localhost:${serverInfo.port}/api/media/thumbnail/photo.png',
          );
          // 第一次请求（生成 + 写缓存）
          final res1 = await http.get(url).timeout(const Duration(seconds: 10));
          expect(res1.statusCode, 200, reason: 'Response body: ${res1.body}');
          expect(res1.headers['content-type'], contains('image/jpeg'));
          // JPEG 以 0xFF 0xD8 开头
          expect(res1.bodyBytes[0], 0xFF);
          expect(res1.bodyBytes[1], 0xD8);
          // 第二次请求（应命中缓存），数据与首次一致
          final res2 = await http.get(url);
          expect(res2.statusCode, 200);
          expect(res2.bodyBytes, res1.bodyBytes);
        } finally {
          await serverInfo.server.stop();
        }
      });

      test('错误状态矩阵：404 / 400 / 403', () async {
        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
          for (final (:name, :path, :expected) in [
            (name: '不存在的文件', path: '/nonexistent.jpg', expected: 404),
            (name: '缺少路径', path: '/', expected: 400),
            (name: '路径穿越', path: '/..%2F..%2Fetc', expected: 403),
          ]) {
            final url = Uri.parse(
              'http://localhost:${serverInfo.port}/api/media/thumbnail$path',
            );
            final response = await http.get(url);
            expect(
              response.statusCode,
              expected,
              reason: 'case: $name, URI: $url',
            );
          }

          // 404 错误体包含「文件不存在」提示
          final url = Uri.parse(
            'http://localhost:${serverInfo.port}/api/media/thumbnail/nonexistent.jpg',
          );
          final response = await http.get(url);
          expect(response.statusCode, 404);
          final body = jsonDecode(response.body);
          expect(body['error'], contains('文件不存在'));
        } finally {
          await serverInfo.server.stop();
        }
      });

      test('中文路径正常工作（覆盖 URI 解码）', () async {
        final chineseDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}妹妹',
        );
        chineseDir.createSync();
        final imgFile = File(
          '${chineseDir.path}${Platform.pathSeparator}照片.png',
        );
        await imgFile.writeAsBytes(validPng);

        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
          final encodedPath = '/%E5%A6%B9%E5%A6%B9/%E7%85%A7%E7%89%87.png';
          final url = Uri.parse(
            'http://localhost:${serverInfo.port}/api/media/thumbnail$encodedPath',
          );
          final response = await http.get(url);
          expect(response.statusCode, 200);
        } finally {
          await serverInfo.server.stop();
        }
      });
    });
  });
}
