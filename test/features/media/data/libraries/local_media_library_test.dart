import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/data/libraries/local_media_library.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_cache.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_generator.dart';
import 'package:oh_my_llm/features/media/data/scanning/thumbnail_process_runner.dart';

/// 构造一个不触碰平台通道与 ffmpeg 的本地媒体库（列表/资产用例不调用生成器）。
LocalMediaLibrary buildLocalLibraryForTest(Directory root) {
  final scanner = MediaDirectoryScanner(root.path);
  return LocalMediaLibrary(
    scanner: scanner,
    cache: MediaThumbnailCache.custom(
      Directory('${root.path}${Platform.pathSeparator}.thumbnail-test-cache'),
    ),
    generator: MediaThumbnailGenerator(
      scanner: scanner,
      processRunner: const DartThumbnailProcessRunner(),
    ),
  );
}

/// 受控假生成器：不读取源文件，因此绝不会进入 package:image 或 ffmpeg 代码。
final class FakeMediaThumbnailGenerator extends MediaThumbnailGenerator {
  FakeMediaThumbnailGenerator(MediaDirectoryScanner scanner)
    : super(
        scanner: scanner,
        processRunner: const DartThumbnailProcessRunner(),
      );

  final List<String> calls = [];
  List<int> bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  ThumbnailException? failure;

  @override
  Future<List<int>> generate(String relativePath) async {
    calls.add(relativePath);
    final configuredFailure = failure;
    if (configuredFailure != null) throw configuredFailure;
    return bytes;
  }
}

/// 使用受控假生成器构造本地媒体库（缩略图用例专用，每次测试新建一个假实例）。
LocalMediaLibrary buildLocalLibraryWithFakeGenerator(
  Directory root,
  FakeMediaThumbnailGenerator generator,
) {
  final scanner = MediaDirectoryScanner(root.path);
  return LocalMediaLibrary(
    scanner: scanner,
    cache: MediaThumbnailCache.custom(
      Directory('${root.path}${Platform.pathSeparator}.thumbnail-test-cache'),
    ),
    generator: generator,
  );
}

void main() {
  group('LocalMediaLibrary 列表与资产解析', () {
    test(
      'lists root and resolves Chinese local image/video file URIs',
      () async {
        final root = await Directory.systemTemp.createTemp('omll_local_media_');
        addTearDown(() => root.delete(recursive: true));
        final album = Directory('${root.path}${Platform.pathSeparator}相册')
          ..createSync();
        final image = File('${album.path}${Platform.pathSeparator}猫.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final video = File('${album.path}${Platform.pathSeparator}猫.mp4')
          ..writeAsBytesSync([4, 5, 6]);
        final library = buildLocalLibraryForTest(root);

        final items = await library.listDirectory('/相册');
        final imageResource = await library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: '/相册/猫.jpg',
          ),
        );
        final videoResource = await library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.video,
            relativePath: '/相册/猫.mp4',
          ),
        );

        expect(items.map((item) => item.name), containsAll(['猫.jpg', '猫.mp4']));
        // %TEMP% 可能是 8.3 短名（如 HINANA~1），而资源 URI 来自经
        // resolveSymbolicLinksSync 归一化的长名路径；两侧都归一化再比较，
        // 与 media_directory_scanner_test 的既有做法一致。
        expect(
          File.fromUri(imageResource.uri).absolute.path.toLowerCase(),
          image.resolveSymbolicLinksSync().toLowerCase(),
        );
        expect(
          File.fromUri(videoResource.uri).absolute.path.toLowerCase(),
          video.resolveSymbolicLinksSync().toLowerCase(),
        );
      },
    );

    test('路径穿越在列表与资产操作均映射为 invalidPath', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final library = buildLocalLibraryForTest(root);

      await expectLater(
        library.listDirectory('/../outside'),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.invalidPath,
          ),
        ),
      );
      await expectLater(
        library.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: '/../outside.jpg',
          ),
        ),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.invalidPath,
          ),
        ),
      );
    });

    test('缺失根目录映射为 sourceUnavailable，缺失资产映射为 notFound', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));

      // 根目录不存在：列表操作应为 sourceUnavailable
      final missingRoot = Directory(
        '${root.path}${Platform.pathSeparator}does-not-exist',
      );
      final rootLibrary = buildLocalLibraryForTest(missingRoot);
      await expectLater(
        rootLibrary.listDirectory('/'),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.sourceUnavailable,
          ),
        ),
      );

      // 根目录存在但资产缺失：资产操作应为 notFound
      final assetLibrary = buildLocalLibraryForTest(root);
      await expectLater(
        assetLibrary.resolveAsset(
          const MediaAssetRequest(
            kind: MediaAssetKind.image,
            relativePath: '/缺失.jpg',
          ),
        ),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.notFound,
          ),
        ),
      );
    });

    test('图片请求携带视频扩展名映射为 unsupportedMedia', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final library = buildLocalLibraryForTest(root);

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
    });

    test('递归视频委托扫描器并保留相对路径', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      Directory(
        '${root.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep',
      ).createSync(recursive: true);
      File(
        '${root.path}${Platform.pathSeparator}video1.mp4',
      ).writeAsStringSync('v1');
      File(
        '${root.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep${Platform.pathSeparator}video2.mkv',
      ).writeAsStringSync('v2');
      File(
        '${root.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}照片.jpg',
      ).writeAsStringSync('img');

      final library = buildLocalLibraryForTest(root);
      final videos = await library.listVideosRecursively('/');

      expect(videos.length, 2);
      expect(
        videos.map((v) => v.name),
        containsAll(['video1.mp4', 'video2.mkv']),
      );
      final deep = videos.firstWhere((v) => v.name == 'video2.mkv');
      expect(
        deep.relativePath.toLowerCase(),
        endsWith('/sub/deep/video2.mkv'.toLowerCase()),
      );
    });

    test('本地资源为 file scheme 且不含 HTTP authority', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}${Platform.pathSeparator}a.jpg',
      ).writeAsBytesSync([1, 2, 3]);
      final library = buildLocalLibraryForTest(root);

      final resource = await library.resolveAsset(
        const MediaAssetRequest(
          kind: MediaAssetKind.image,
          relativePath: '/a.jpg',
        ),
      );
      expect(resource, isA<LocalMediaResource>());
      expect(resource.uri.scheme, 'file');
      expect(resource.uri.isAbsolute, isTrue);
      expect(resource.uri.authority, isEmpty);
      expect(resource.uri.toString(), isNot(contains('http')));
    });
  });

  group('LocalMediaLibrary 缩略图解析', () {
    test('hasThumbnail 为 false 返回 null 且不调用生成器', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final generator = FakeMediaThumbnailGenerator(
        MediaDirectoryScanner(root.path),
      );
      final library = buildLocalLibraryWithFakeGenerator(root, generator);

      final result = await library.resolveThumbnail(
        const MediaThumbnailRequest(
          relativePath: '/猫.mp4',
          sizeBytes: 1,
          lastModified: 2,
          hasThumbnail: false,
        ),
      );
      expect(result, isNull);
      expect(generator.calls, isEmpty);
    });

    test('首次解析生成字节、写入缓存并返回缓存文件资源', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final generator = FakeMediaThumbnailGenerator(
        MediaDirectoryScanner(root.path),
      );
      final library = buildLocalLibraryWithFakeGenerator(root, generator);

      final result = await library.resolveThumbnail(
        const MediaThumbnailRequest(
          relativePath: '/猫.mp4',
          sizeBytes: 1,
          lastModified: 2,
          hasThumbnail: true,
        ),
      );

      expect(generator.calls, ['/猫.mp4']);
      expect(result, isA<LocalMediaResource>());
      final cacheFile = File.fromUri(result!.uri);
      expect(cacheFile.existsSync(), isTrue);
      expect(cacheFile.readAsBytesSync(), generator.bytes);
    });

    test('第二次相同请求命中缓存且生成器调用次数保持一次', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final generator = FakeMediaThumbnailGenerator(
        MediaDirectoryScanner(root.path),
      );
      final library = buildLocalLibraryWithFakeGenerator(root, generator);
      const request = MediaThumbnailRequest(
        relativePath: '/猫.mp4',
        sizeBytes: 1,
        lastModified: 2,
        hasThumbnail: true,
      );

      final first = await library.resolveThumbnail(request);
      final second = await library.resolveThumbnail(request);

      expect(generator.calls, hasLength(1));
      expect(second!.uri, first!.uri);
    });

    test('size 或 lastModified 变化使用不同缓存键并再次调用生成器', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final generator = FakeMediaThumbnailGenerator(
        MediaDirectoryScanner(root.path),
      );
      final library = buildLocalLibraryWithFakeGenerator(root, generator);
      const base = MediaThumbnailRequest(
        relativePath: '/猫.mp4',
        sizeBytes: 100,
        lastModified: 200,
        hasThumbnail: true,
      );

      await library.resolveThumbnail(base);
      expect(generator.calls, hasLength(1));

      await library.resolveThumbnail(
        const MediaThumbnailRequest(
          relativePath: '/猫.mp4',
          sizeBytes: 101,
          lastModified: 200,
          hasThumbnail: true,
        ),
      );
      expect(generator.calls, hasLength(2));

      await library.resolveThumbnail(
        const MediaThumbnailRequest(
          relativePath: '/猫.mp4',
          sizeBytes: 100,
          lastModified: 201,
          hasThumbnail: true,
        ),
      );
      expect(generator.calls, hasLength(3));
    });

    test('ThumbnailException 映射为 thumbnailUnavailable', () async {
      final root = await Directory.systemTemp.createTemp('omll_local_media_');
      addTearDown(() => root.delete(recursive: true));
      final generator = FakeMediaThumbnailGenerator(
        MediaDirectoryScanner(root.path),
      );
      generator.failure = ThumbnailException('模拟生成失败');
      final library = buildLocalLibraryWithFakeGenerator(root, generator);

      await expectLater(
        library.resolveThumbnail(
          const MediaThumbnailRequest(
            relativePath: '/猫.mp4',
            sizeBytes: 1,
            lastModified: 2,
            hasThumbnail: true,
          ),
        ),
        throwsA(
          isA<MediaLibraryFailure>().having(
            (e) => e.code,
            'code',
            MediaLibraryFailureCode.thumbnailUnavailable,
          ),
        ),
      );
      expect(generator.calls, ['/猫.mp4']);
    });
  });
}
