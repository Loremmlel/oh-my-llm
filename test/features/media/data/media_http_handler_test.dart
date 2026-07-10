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
      File('${tempRoot.path}${Platform.pathSeparator}photo.jpg').writeAsStringSync(
        'fake image',
      );
      File('${tempRoot.path}${Platform.pathSeparator}video.mp4').writeAsStringSync(
        'fake video',
      );
      File('${tempRoot.path}${Platform.pathSeparator}subdir${Platform.pathSeparator}nested.png')
          .writeAsStringSync('nested image');

      server = SyncHttpServer();
      port = await server.start(
        handlers: [MediaHttpHandler(scanner: scanner)],
      );
    });

    tearDown(() async {
      if (server.isRunning) await server.stop();
      tempRoot.deleteSync(recursive: true);
    });

    test('GET /api/media/list/ 返回根目录列表', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      final body = jsonDecode(response.body) as List;
      expect(body.length, 3);
      final names = body.map((e) => e['name'] as String).toList();
      expect(names, containsAll(['photo.jpg', 'video.mp4', 'subdir']));
    });

    test('GET /api/media/list 返回根目录列表', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 3);
    });

    test('子目录扫描正确', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/subdir'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 1);
      expect(body[0]['name'], 'nested.png');
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

    test('中文路径正常工作', () async {
      final chineseDir = Directory('${tempRoot.path}${Platform.pathSeparator}妹妹');
      chineseDir.createSync();
      File('${chineseDir.path}${Platform.pathSeparator}照片.jpg')
          .writeAsStringSync('chinese photo');

      final encodedPath = '/%E5%A6%B9%E5%A6%B9';
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list$encodedPath'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 1);
      expect(body[0]['name'], '照片.jpg');
    });

    test('目录条目包含 type: directory', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      final dirItem = body.firstWhere((e) => e['name'] == 'subdir');
      expect(dirItem['type'], 'directory');
    });

    test('文件条目包含 mimeType', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/media/list/'),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      final videoItem = body.firstWhere((e) => e['name'] == 'video.mp4');
      expect(videoItem['mimeType'], 'video/mp4');
      expect(videoItem['type'], 'file');
    });
  });
}
