import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_cache.dart';

void main() {
  group('MediaThumbnailCache', () {
    late Directory tempDir;
    late MediaThumbnailCache cache;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('thumbnail_cache_test_');
      cache = MediaThumbnailCache.custom(
        Directory('${tempDir.path}/.cache/thumbnails'),
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('computeKey', () {
      test('相同输入产生相同 key', () {
        final k1 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        final k2 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        expect(k1, k2);
      });

      test('不同 relativePath 产生不同 key', () {
        final k1 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        final k2 = MediaThumbnailCache.computeKey('/a/c.mp4', 100, 200);
        expect(k1, isNot(k2));
      });

      test('不同 fileSize 产生不同 key', () {
        final k1 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        final k2 = MediaThumbnailCache.computeKey('/a/b.mp4', 200, 200);
        expect(k1, isNot(k2));
      });

      test('不同 lastModified 产生不同 key', () {
        final k1 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        final k2 = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 300);
        expect(k1, isNot(k2));
      });

      test('key 只包含十六进制字符（32 位 MD5 hex）', () {
        final key = MediaThumbnailCache.computeKey('/test.mp4', 0, 0);
        expect(key.length, 32);
        expect(RegExp(r'^[a-f0-9]+$').hasMatch(key), isTrue);
      });

      test('中文路径正常工作', () {
        final key = MediaThumbnailCache.computeKey('/妹妹/视频.mp4', 100, 200);
        expect(key, isNotEmpty);
        expect(key.length, 32);
      });
    });

    group('get/put', () {
      test('缓存未命中返回 null', () {
        final result = cache.get('/test.jpg', 100, 200);
        expect(result, isNull);
      });

      test('put 后 get 命中', () async {
        final bytes = [0xFF, 0xD8, 0xFF, 0xE0]; // JPEG header
        await cache.put('/test.jpg', 100, 200, bytes);
        final result = cache.get('/test.jpg', 100, 200);
        expect(result, isNotNull);
        expect(result!.existsSync(), isTrue);
      });

      test('文件更新（size 变化）后旧缓存 miss', () async {
        await cache.put('/test.jpg', 100, 200, [0xFF, 0xD8]);
        // 文件大小变了 → 不同 key → 旧缓存查询应返回 null
        final result = cache.get('/test.jpg', 200, 200);
        expect(result, isNull);
      });

      test('自动创建缓存目录', () async {
        // 确保目录不存在
        if (cache.cacheDir.existsSync()) {
          cache.cacheDir.deleteSync(recursive: true);
        }
        await cache.put('/test.jpg', 100, 200, [0xFF, 0xD8]);
        expect(cache.cacheDir.existsSync(), isTrue);
      });
    });
  });
}
