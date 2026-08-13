import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/data/scanning/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/http/media_image_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';

void main() {
  group('MediaImageHttpHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late SyncHttpServer server;
    late int port;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('image_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 创建子目录和测试文件
      final subDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}subdir',
      );
      subDir.createSync();
      File(
        '${tempRoot.path}${Platform.pathSeparator}test.jpg',
      ).writeAsStringSync('fake-jpeg-content-12345');
      File(
        '${subDir.path}${Platform.pathSeparator}nested.png',
      ).writeAsStringSync('fake-png-content');
      // 中文路径
      final chineseDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}照片',
      );
      chineseDir.createSync();
      File(
        '${chineseDir.path}${Platform.pathSeparator}小猫.jpg',
      ).writeAsStringSync('chinese-path-content');

      server = SyncHttpServer();
      port = await server.start(
        handlers: [MediaImageHttpHandler(scanner: scanner)],
      );
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    test('根目录与子目录图片返回 200 + 正确 Content-Type/Accept-Ranges', () async {
      for (final (:name, :path, :contentType, :expectedBody) in [
        (
          name: '根目录 test.jpg',
          path: '/test.jpg',
          contentType: 'image/jpeg',
          expectedBody: 'fake-jpeg-content-12345'.codeUnits,
        ),
        (
          name: '子目录 nested.png',
          path: '/subdir/nested.png',
          contentType: 'image/png',
          expectedBody: 'fake-png-content'.codeUnits,
        ),
      ]) {
        final response = await http.get(
          Uri.parse('http://127.0.0.1:$port/api/media/image$path'),
        );

        expect(response.statusCode, 200, reason: 'case: $name');
        expect(
          response.headers['content-type'],
          contains(contentType),
          reason: 'case: $name',
        );
        expect(
          response.headers['accept-ranges'],
          'bytes',
          reason: 'case: $name',
        );
        expect(
          response.bodyBytes.toList(),
          expectedBody,
          reason: 'case: $name',
        );
      }
    });

    test('无路径返回 400', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/'),
      );

      expect(response.statusCode, 400);
    });

    test('不存在的文件返回 404', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/不存在.jpg'),
      );

      expect(response.statusCode, 404);
    });

    test('非图片扩展名仍返回 200（不校验扩展名）', () async {
      File(
        '${tempRoot.path}${Platform.pathSeparator}doc.txt',
      ).writeAsStringSync('text file');
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/doc.txt'),
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        contains('application/octet-stream'),
      );
    });
  });
}
