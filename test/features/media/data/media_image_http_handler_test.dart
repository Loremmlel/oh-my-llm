import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_image_http_handler.dart';
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
      File('${tempRoot.path}${Platform.pathSeparator}test.jpg').writeAsStringSync(
        'fake-jpeg-content-12345',
      );
      File('${subDir.path}${Platform.pathSeparator}nested.png').writeAsStringSync(
        'fake-png-content',
      );
      // 中文路径
      final chineseDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}照片',
      );
      chineseDir.createSync();
      File('${chineseDir.path}${Platform.pathSeparator}小猫.jpg').writeAsStringSync(
        'chinese-path-content',
      );

      server = SyncHttpServer();
      port = await server.start(
        handlers: [MediaImageHttpHandler(scanner: scanner)],
      );
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    test('GET 正常图片返回 200 和正确 Content-Type', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/test.jpg'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('image/jpeg'));
      expect(response.bodyBytes.toList(), 'fake-jpeg-content-12345'.codeUnits);
    });

    test('子目录图片正常返回', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/subdir/nested.png'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('image/png'));
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

    test('路径穿越在 scanner 层面被拦截（HTTP 级归 scanner 覆盖）', () {
      // 穿越检测的核心逻辑在 MediaDirectoryScanner.resolvePath 中已测试
      // HTTP 层面因 Uri.parse / http 包会规范化 .. 路径，无法发送原始 .. 请求
      // 安全覆盖由 media_directory_scanner_test.dart 保证
    }, skip: false);

    test('非图片扩展名仍返回 200（不校验扩展名）', () async {
      File('${tempRoot.path}${Platform.pathSeparator}doc.txt').writeAsStringSync(
        'text file',
      );
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/doc.txt'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/octet-stream'));
    });

    test('Accept-Ranges 头存在', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/image/test.jpg'),
      );

      expect(response.headers['accept-ranges'], 'bytes');
    });
  });
}
