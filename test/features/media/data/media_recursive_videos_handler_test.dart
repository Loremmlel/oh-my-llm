import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_recursive_videos_handler.dart';

void main() {
  group('MediaRecursiveVideosHandler', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late HttpRouteHandler handler;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('handler_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);
      handler = MediaRecursiveVideosHandler(scanner: scanner);

      // 创建测试视频
      Directory('${tempRoot.path}${Platform.pathSeparator}sub').createSync();
      File('${tempRoot.path}${Platform.pathSeparator}video1.mp4')
          .writeAsStringSync('v1');
      File('${tempRoot.path}${Platform.pathSeparator}sub${Platform.pathSeparator}video2.mp4')
          .writeAsStringSync('v2');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    for (final path in [
      '/api/media/videos/recursive/sister',
      '/api/media/videos/recursive',
    ]) {
      test('canHandle 匹配 GET $path', () {
        final req = _FakeHttpRequest('GET', path);
        expect(handler.canHandle(req), isTrue);
      });
    }

    test('canHandle 拒绝 POST 请求', () {
      final req = _FakeHttpRequest('POST', '/api/media/videos/recursive/sister');
      expect(handler.canHandle(req), isFalse);
    });

    test('canHandle 拒绝其他路径前缀', () {
      final req = _FakeHttpRequest('GET', '/api/media/list/sister');
      expect(handler.canHandle(req), isFalse);
    });

    test('handle 返回 200 和 JSON 视频列表（递归扫描子目录）', () async {
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive');
      await handler.handle(req);
      expect(req.response.statusCode, 200);
      final body = jsonDecode((req.response as _FakeHttpResponse).body) as List;
      expect(body.length, 2);
      expect(body[0]['name'], 'video1.mp4');
      expect(body[1]['name'], 'video2.mp4');
    });

    test('handle 路径穿越返回 403', () async {
      // PathTraversalException 由 MediaDirectoryScanner.resolvePath 在
      // 扫描器层面检测并抛出。在 HTTP 层面，Dart 的 Uri 类始终规范化路径中
      // 的 .. 段（包括 %2e%2e 编码），因此无法通过 URL 路径触发此异常。
      // 此处通过模拟扫描器验证 Handler 正确捕获并返回 403。
      final throwingHandler = MediaRecursiveVideosHandler(
        scanner: _TraversalScanner(tempRoot.path),
      );
      final req = _FakeHttpRequest('GET', '/api/media/videos/recursive');
      await throwingHandler.handle(req);
      expect(req.response.statusCode, 403);
    });
  });
}

/// 模拟抛出 PathTraversalException 的扫描器。
class _TraversalScanner extends MediaDirectoryScanner {
  _TraversalScanner(super.rootDirectory);

  @override
  Future<List<VideoItem>> scanRecursiveVideos(String relativePath) async {
    throw PathTraversalException(relativePath);
  }
}

/// 可控制的假 HttpRequest，仅覆盖 canHandle 所需字段。
class _FakeHttpRequest extends Fake implements HttpRequest {
  @override
  final String method;
  @override
  final Uri uri;

  _FakeHttpRequest(this.method, String path) : uri = Uri.parse(path);

  @override
  late final HttpResponse response = _FakeHttpResponse();
}

/// 收集写入数据的假 HttpResponse。
class _FakeHttpResponse extends Fake implements HttpResponse {
  @override
  int statusCode = 200;
  final _buffer = StringBuffer();

  @override
  HttpHeaders get headers => _FakeHttpHeaders();
  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  String get body => _buffer.toString();

  @override
  Future<void> close() async {}
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}
