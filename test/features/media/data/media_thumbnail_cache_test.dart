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
      test('确定性输出：中文路径的 32 位小写十六进制 key', () {
        final k1 = MediaThumbnailCache.computeKey('/妹妹/视频.mp4', 100, 200);
        final k2 = MediaThumbnailCache.computeKey('/妹妹/视频.mp4', 100, 200);
        expect(k1, k2);
        expect(k1.length, 32);
        expect(RegExp(r'^[a-f0-9]+$').hasMatch(k1), isTrue);
      });

      test('任一输入变化产生不同 key', () {
        final base = MediaThumbnailCache.computeKey('/a/b.mp4', 100, 200);
        for (final (:name, :path, :size, :modified) in [
          (name: 'relativePath 变化', path: '/a/c.mp4', size: 100, modified: 200),
          (name: 'fileSize 变化', path: '/a/b.mp4', size: 200, modified: 200),
          (name: 'lastModified 变化', path: '/a/b.mp4', size: 100, modified: 300),
        ]) {
          expect(
            MediaThumbnailCache.computeKey(path, size, modified),
            isNot(base),
            reason: 'case: $name',
          );
        }
      });
    });

    group('get/put', () {
      test('缺失目录 → miss → put 建目录并命中 → size 变化后 miss', () async {
        // 确保目录不存在
        if (cache.cacheDir.existsSync()) {
          cache.cacheDir.deleteSync(recursive: true);
        }
        expect(cache.cacheDir.existsSync(), isFalse);

        // 缓存未命中返回 null
        expect(cache.get('/test.jpg', 100, 200), isNull);

        // put 后自动创建缓存目录
        await cache.put('/test.jpg', 100, 200, [0xFF, 0xD8, 0xFF, 0xE0]);
        expect(cache.cacheDir.existsSync(), isTrue);

        // put 后 get 命中
        final result = cache.get('/test.jpg', 100, 200);
        expect(result, isNotNull);
        expect(result!.existsSync(), isTrue);

        // 文件大小变了 → 不同 key → 旧缓存查询应返回 null
        expect(cache.get('/test.jpg', 200, 200), isNull);
      });
    });
  });
}
