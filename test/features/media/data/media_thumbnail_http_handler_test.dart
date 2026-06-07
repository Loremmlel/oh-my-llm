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
    late MediaDirectoryScanner scanner;
    late MediaThumbnailCache cache;
    late MediaThumbnailGenerator generator;
    late MediaThumbnailHttpHandler handler;
    late List<int> validPng;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('thumbnail_http_test_');
      scanner = MediaDirectoryScanner(tempDir.path);
      cache = MediaThumbnailCache.custom(
        Directory('${tempDir.path}/.cache/thumbnails'),
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
      tempDir.deleteSync(recursive: true);
    });

    group('handle — 图片缩略图', () {
      test('返回 200 + image/jpeg', () async {
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
          final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

          expect(response.statusCode, 200,
              reason: 'Response body: ${response.body}');
          expect(response.headers['content-type'], contains('image/jpeg'));
          // JPEG 以 0xFF 0xD8 开头
          expect(response.bodyBytes[0], 0xFF);
          expect(response.bodyBytes[1], 0xD8);
        } finally {
          await serverInfo.server.stop();
        }
      });

      test('缓存命中返回 200 且数据一致', () async {
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
          // 第一次请求（生成 + 缓存）
          final res1 = await http.get(url);
          expect(res1.statusCode, 200);
          // 第二次请求（应命中缓存）
          final res2 = await http.get(url);
          expect(res2.statusCode, 200);
          // 两次返回相同的 JPEG 数据
          expect(res2.bodyBytes, res1.bodyBytes);
        } finally {
          await serverInfo.server.stop();
        }
      });

      test('不存在的文件返回 404', () async {
        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
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

      test('缺少路径返回 400', () async {
        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
          final url = Uri.parse(
            'http://localhost:${serverInfo.port}/api/media/thumbnail/',
          );
          final response = await http.get(url);
          expect(response.statusCode, 400);
        } finally {
          await serverInfo.server.stop();
        }
      });

      test('中文路径正常工作', () async {
        final chineseDir = Directory('${tempDir.path}${Platform.pathSeparator}妹妹');
        chineseDir.createSync();
        final imgFile = File('${chineseDir.path}${Platform.pathSeparator}照片.png');
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

      test('路径穿越被拒绝', () async {
        final serverInfo = await _startTestServer(
          scanner: scanner,
          handler: handler,
        );

        try {
          final url = Uri.parse(
            'http://localhost:${serverInfo.port}/api/media/thumbnail/..%2F..%2Fetc',
          );
          final response = await http.get(url);
          expect(response.statusCode, 403);
        } finally {
          await serverInfo.server.stop();
        }
      });
    });
  });
}
