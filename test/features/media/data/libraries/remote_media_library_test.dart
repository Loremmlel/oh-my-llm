import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/data/libraries/remote_media_library.dart';

const _baseUri = 'http://192.168.1.5:8080';

void main() {
  group('RemoteMediaLibrary URI 构造与列表解析', () {
    test('encodes each directory segment and parses the list DTO', () async {
      final requests = <http.Request>[];
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            utf8.encode(
              '[{"type":"file","name":"猫.jpg",'
              '"relativePath":"/相册/猫.jpg","size":10,'
              '"lastModified":20,"mimeType":"image/jpeg",'
              '"thumbnailUrl":"/api/media/thumbnail/相册/猫.jpg"}]',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final items = await library.listDirectory('/相册/旅行 2026');
      expect(
        requests.single.url.toString(),
        'http://192.168.1.5:8080/api/media/list/%E7%9B%B8%E5%86%8C/'
        '%E6%97%85%E8%A1%8C%202026',
      );
      expect(items.single.hasThumbnail, isTrue);
    });

    test(
      'resolving image video and thumbnail performs no HTTP preflight',
      () async {
        var requestCount = 0;
        final library = RemoteMediaLibrary(
          baseUri: Uri.parse(_baseUri),
          httpClient: MockClient((_) async {
            requestCount++;
            return http.Response('', 500);
          }),
        );
        final image = await library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: '/相册/猫.jpg',
          ),
        );
        final video = await library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.video,
            relativePath: '/视频/猫.mp4',
          ),
        );
        final thumb = await library.resolveThumbnail(
          const MediaThumbnailRequest(
            relativePath: '/视频/猫.mp4',
            sizeBytes: 1,
            lastModified: 2,
            hasThumbnail: true,
          ),
        );
        expect(requestCount, 0);
        // Dart 的 Uri.path 返回百分号编码后的路径，语义等价断言用解码后的
        // pathSegments 还原，保证「解析到正确端点与相对路径」的契约不变。
        expect(
          '/${image.uri.pathSegments.join('/')}',
          '/api/media/image/相册/猫.jpg',
        );
        expect(
          '/${video.uri.pathSegments.join('/')}',
          '/api/media/video/视频/猫.mp4',
        );
        expect(
          '/${thumb!.uri.pathSegments.join('/')}',
          '/api/media/thumbnail/视频/猫.mp4',
        );
      },
    );

    test('listVideosRecursively 命中递归端点并解析视频列表', () async {
      final requests = <http.Request>[];
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            utf8.encode('[{"name":"猫.mp4","relativePath":"/视频/猫.mp4"}]'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final videos = await library.listVideosRecursively('/视频');
      expect(
        requests.single.url.toString(),
        'http://192.168.1.5:8080/api/media/videos/recursive/%E8%A7%86%E9%A2%91',
      );
      expect(videos.single.relativePath, '/视频/猫.mp4');
    });
  });

  group('RemoteMediaLibrary 状态码与传输失败映射', () {
    final statusCases = <({int status, MediaLibraryFailureCode code})>[
      (status: 400, code: MediaLibraryFailureCode.invalidPath),
      (status: 403, code: MediaLibraryFailureCode.invalidPath),
      (status: 404, code: MediaLibraryFailureCode.notFound),
      (status: 408, code: MediaLibraryFailureCode.timeout),
      (status: 500, code: MediaLibraryFailureCode.invalidResponse),
    ];

    for (final (:status, :code) in statusCases) {
      test('listDirectory 状态 $status 映射为 $code', () async {
        final library = RemoteMediaLibrary(
          baseUri: Uri.parse(_baseUri),
          httpClient: MockClient((_) async => http.Response('{}', status)),
        );
        await expectLater(
          library.listDirectory('/'),
          throwsA(
            isA<MediaLibraryFailure>().having((e) => e.code, 'code', code),
          ),
        );
      });
    }

    test('客户端网络错误映射为 networkUnavailable', () async {
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) async => throw http.ClientException('拒绝连接')),
      );
      await expectLater(
        library.listDirectory('/'),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.networkUnavailable,
          ),
        ),
      );
    });

    test('请求超时映射为 timeout（注入 1ms 超时，Completer 由 tearDown 释放）', () async {
      final completer = Completer<http.Response>();
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(http.Response('', 200));
        }
      });
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) => completer.future),
        directoryTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        library.listDirectory('/'),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.timeout,
          ),
        ),
      );
    });

    test('200 响应但列表 JSON 损坏映射为 invalidResponse', () async {
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(
        library.listDirectory('/'),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.invalidResponse,
          ),
        ),
      );
    });
  });

  group('RemoteMediaLibrary 非法输入', () {
    test('非法相对路径不发请求并映射为 invalidPath', () async {
      var requestCount = 0;
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) async {
          requestCount++;
          return http.Response('[]', 200);
        }),
      );
      for (final path in const [
        '',
        '缺前导斜杠',
        '/a/../b.jpg',
        '/a/./b.jpg',
        '/..',
      ]) {
        await expectLater(
          library.listDirectory(path),
          throwsA(
            isA<MediaLibraryFailure>().having(
              (e) => e.code,
              'code',
              MediaLibraryFailureCode.invalidPath,
            ),
          ),
          reason: 'case: $path',
        );
      }
      expect(requestCount, 0);
    });

    test('扩展名与媒体类型不匹配映射为 unsupportedMedia 且不发请求', () async {
      var requestCount = 0;
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) async {
          requestCount++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: '/a.mp4',
          ),
        ),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.unsupportedMedia,
          ),
        ),
      );
      await expectLater(
        library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.video,
            relativePath: '/a.jpg',
          ),
        ),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.unsupportedMedia,
          ),
        ),
      );
      expect(requestCount, 0);
    });

    test('非法 base URI 在构造时抛 ArgumentError', () {
      for (final uri in const [
        'ftp://192.168.1.5:8080',
        'http://',
        'http://user:pass@192.168.1.5:8080',
        'http://192.168.1.5:8080?q=1',
        'http://192.168.1.5:8080#frag',
        'http://192.168.1.5:8080/media',
      ]) {
        expect(
          () => RemoteMediaLibrary(
            baseUri: Uri.parse(uri),
            httpClient: MockClient((_) async => http.Response('[]', 200)),
          ),
          throwsArgumentError,
          reason: 'case: $uri',
        );
      }
    });

    test('hasThumbnail 为 false 时 resolveThumbnail 返回 null', () async {
      var requestCount = 0;
      final library = RemoteMediaLibrary(
        baseUri: Uri.parse(_baseUri),
        httpClient: MockClient((_) async {
          requestCount++;
          return http.Response('', 500);
        }),
      );
      final thumb = await library.resolveThumbnail(
        const MediaThumbnailRequest(
          relativePath: '/视频/猫.mp4',
          sizeBytes: 1,
          lastModified: 2,
          hasThumbnail: false,
        ),
      );
      expect(thumb, isNull);
      expect(requestCount, 0);
    });
  });
}
