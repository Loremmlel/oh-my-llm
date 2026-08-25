import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/data/scanning/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/http/media_video_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/http/sync_http_server.dart';

void main() {
  group('MediaVideoHttpHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late SyncHttpServer server;
    late int port;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('video_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 创建测试视频文件（8200 字节的可控内容，字节值 = 下标 % 256）
      File('${tempRoot.path}${Platform.pathSeparator}test.mp4')
          .writeAsBytesSync(List.generate(8200, (i) => i % 256));

      server = SyncHttpServer();
      port = await server.start(
        handlers: [MediaVideoHttpHandler(scanner: scanner)],
      );
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    test('无 Range 头返回 200 和完整文件', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['content-type'], contains('video/mp4'));
      expect(response.bodyBytes.length, 8200);
    });

    test('Range 矩阵：闭区间/单字节/开放区间/完整开放/后缀', () async {
      final uri = Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4');
      for (final (:name, :range, :contentRange, :length, :first, :last) in [
        (
          name: 'bytes=0-999 闭区间',
          range: 'bytes=0-999',
          contentRange: 'bytes 0-999/8200',
          length: 1000,
          first: 0,
          last: 231,
        ),
        (
          name: 'bytes=100-200 闭区间',
          range: 'bytes=100-200',
          contentRange: 'bytes 100-200/8200',
          length: 101,
          first: 100,
          last: 200,
        ),
        (
          name: 'bytes=0-0 单字节',
          range: 'bytes=0-0',
          contentRange: 'bytes 0-0/8200',
          length: 1,
          first: 0,
          last: 0,
        ),
        (
          name: 'bytes=1000- 开放区间',
          range: 'bytes=1000-',
          contentRange: 'bytes 1000-8199/8200',
          length: 7200,
          first: 232,
          last: 7,
        ),
        (
          name: 'bytes=0- 完整开放区间',
          range: 'bytes=0-',
          contentRange: 'bytes 0-8199/8200',
          length: 8200,
          first: 0,
          last: 7,
        ),
        (
          name: 'bytes=-500 后缀区间',
          range: 'bytes=-500',
          contentRange: 'bytes 7700-8199/8200',
          length: 500,
          first: 20,
          last: 7,
        ),
      ]) {
        final response = await http.get(uri, headers: {'Range': range});

        expect(response.statusCode, 206, reason: 'case: $name');
        expect(
          response.headers['content-range'],
          contentRange,
          reason: 'case: $name',
        );
        expect(response.bodyBytes.length, length, reason: 'case: $name');
        expect(response.bodyBytes.first, first, reason: 'case: $name');
        expect(response.bodyBytes.last, last, reason: 'case: $name');
      }
    });

    test('无效 Range 返回 416', () async {
      final uri = Uri.parse('http://127.0.0.1:$port/api/media/video/test.mp4');
      for (final (:name, :range) in [
        (name: '越界起点 bytes=99999-', range: 'bytes=99999-'),
        (name: '非法格式 bytes=abc', range: 'bytes=abc'),
        (name: '多区间 bytes=0-100, 200-300', range: 'bytes=0-100, 200-300'),
      ]) {
        final response = await http.get(uri, headers: {'Range': range});
        expect(response.statusCode, 416, reason: 'case: $name');
      }
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
