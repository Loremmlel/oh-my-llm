import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_http_handler.dart';
import 'package:oh_my_llm/features/sync/data/sync_http_server.dart';

void main() {
  group('MediaHttpHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late SyncHttpServer server;
    late int port;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('list_handler_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 创建测试目录结构
      Directory('${tempRoot.path}${Platform.pathSeparator}subdir').createSync();
      File(
        '${tempRoot.path}${Platform.pathSeparator}photo.jpg',
      ).writeAsStringSync('fake image');
      File(
        '${tempRoot.path}${Platform.pathSeparator}video.mp4',
      ).writeAsStringSync('fake video');
      File(
        '${tempRoot.path}${Platform.pathSeparator}subdir${Platform.pathSeparator}nested.png',
      ).writeAsStringSync('nested image');

      server = SyncHttpServer();
      port = await server.start(handlers: [MediaHttpHandler(scanner: scanner)]);
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    test('GET /api/media/list/ 返回根目录列表（含 type/mimeType）', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      final body = jsonDecode(response.body) as List;
      expect(body.length, 3);
      final names = body.map((e) => e['name'] as String).toList();
      expect(names, containsAll(['photo.jpg', 'video.mp4', 'subdir']));

      // 目录条目带 type: directory，文件条目带 type: file 与 mimeType
      final dirItem = body.firstWhere((e) => e['name'] == 'subdir');
      expect(dirItem['type'], 'directory');
      // 目录不输出文件专属键（含 thumbnailUrl）
      expect(dirItem.containsKey('thumbnailUrl'), isFalse);
      final videoItem = body.firstWhere((e) => e['name'] == 'video.mp4');
      expect(videoItem['mimeType'], 'video/mp4');
      expect(videoItem['type'], 'file');
      // 缩略图 wire 键与路径保持字面协议不变
      expect(videoItem['thumbnailUrl'], '/api/media/thumbnail/video.mp4');
    });

    test('GET /api/media/list 无尾斜杠返回根目录列表', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 3);
    });

    test('子目录与中文路径列表', () async {
      final chineseDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}妹妹',
      );
      chineseDir.createSync();
      File(
        '${chineseDir.path}${Platform.pathSeparator}照片.jpg',
      ).writeAsStringSync('chinese photo');

      for (final (:name, :route, :expectedName) in [
        (name: '子目录', route: '/subdir', expectedName: 'nested.png'),
        (name: '中文路径', route: '/%E5%A6%B9%E5%A6%B9', expectedName: '照片.jpg'),
      ]) {
        final response = await http.get(
          Uri.parse('http://127.0.0.1:$port/api/media/list$route'),
        );

        expect(response.statusCode, 200, reason: 'case: $name');
        final body = jsonDecode(response.body) as List;
        expect(body.length, 1, reason: 'case: $name');
        expect(body[0]['name'], expectedName, reason: 'case: $name');
      }
    });

    test('空目录返回 200 + 空数组', () async {
      Directory('${tempRoot.path}${Platform.pathSeparator}empty').createSync();

      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/empty'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body, isEmpty);
    });

    test('不存在的目录返回客户端错误（404 或 500）', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/不存在'),
      );

      // POSIX 上 osError.errorCode==2 返回 404；
      // Windows 上 errorCode 不同，返回 500。两者均非 200。
      expect(response.statusCode, anyOf(404, 500));
    });
  });
}
