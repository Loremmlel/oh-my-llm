import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_video_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';

void main() {
  group('MediaVideoHttpHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late SyncHttpServer server;
    late int port;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('video_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 创建测试视频文件（8200 字节的可控内容）
      File('${tempRoot.path}${Platform.pathSeparator}test.mp4').writeAsBytesSync(
        List.generate(8200, (i) => i % 256),
      );
      File('${tempRoot.path}${Platform.pathSeparator}small.mkv').writeAsBytesSync(
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      );

      server = SyncHttpServer();
      port = await server.start(
        handlers: [MediaVideoHttpHandler(scanner: scanner)],
      );
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    // ── 无 Range 头 → 200 ──

    test('无 Range 头返回 200 和完整文件', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['content-type'], contains('video/mp4'));
      expect(response.bodyBytes.length, 8200);
    });

    test('小文件无 Range 头返回 200', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/small.mkv'),
      );

      expect(response.statusCode, 200);
      expect(response.bodyBytes.length, 10);
    });

    // ── Range: bytes=<start>-<end> → 206 ──

    test('Range: bytes=0-999 返回 206 和正确 Content-Range', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=0-999'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-999/8200');
      expect(response.headers['content-length'], '1000');
      expect(response.bodyBytes.length, 1000);
    });

    test('Range: bytes=100-200 返回 206', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=100-200'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 100-200/8200');
      expect(response.bodyBytes.length, 101);
    });

    test('Range: bytes=0-0 返回 206 单字节', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=0-0'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-0/8200');
      expect(response.bodyBytes.length, 1);
    });

    // ── Range: bytes=<start>- → 206 ──

    test('Range: bytes=1000- 返回 206 和 open-ended 范围', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=1000-'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 1000-8199/8200');
      expect(response.bodyBytes.length, 7200); // 8200 - 1000
    });

    test('Range: bytes=0- 返回 206（open-ended 等同于全文件）', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=0-'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-8199/8200');
      expect(response.bodyBytes.length, 8200);
    });

    // ── Range: bytes=-<suffix> → 206 ──

    test('Range: bytes=-500 返回最后 500 字节', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=-500'},
      );

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 7700-8199/8200');
      expect(response.bodyBytes.length, 500);
    });

    // ── 无效 Range → 416 ──

    test('Range: bytes=99999- 返回 416', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=99999-'},
      );

      expect(response.statusCode, 416);
    });

    test('Range: bytes=abc 返回 416', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=abc'},
      );

      expect(response.statusCode, 416);
    });

    test('多 Range 返回 416', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
        headers: {'Range': 'bytes=0-100, 200-300'},
      );

      expect(response.statusCode, 416);
    });

    // ── 安全 ──

    test('不存在的文件返回 404', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/不存在.mp4'),
      );

      expect(response.statusCode, 404);
    });

    test('无路径返回 400', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/'),
      );

      expect(response.statusCode, 400);
    });
  });
}
