import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

void main() {
  group('FileItem 构造默认值', () {
    test('未指定可选字段时使用默认值', () {
      const item = FileItem(
        name: 'a.mp4',
        isDirectory: false,
        sizeBytes: 1,
        relativePath: '/a.mp4',
      );
      expect(item.lastModified, 0);
      expect(item.mimeType, isNull);
      expect(item.hasThumbnail, isFalse);
    });
  });

  group('FileItem.hasThumbnail', () {
    test('显式声明缩略图信号', () {
      const withThumb = FileItem(
        name: 'a.jpg',
        isDirectory: false,
        sizeBytes: 1,
        relativePath: '/a.jpg',
        hasThumbnail: true,
      );
      const withoutThumb = FileItem(
        name: 'b.mp4',
        isDirectory: false,
        sizeBytes: 1,
        relativePath: '/b.mp4',
        hasThumbnail: false,
      );
      expect(withThumb.hasThumbnail, isTrue);
      expect(withoutThumb.hasThumbnail, isFalse);
    });
  });

  group('FileItem.formattedSize', () {
    test('格式化大小矩阵', () {
      const cases = [
        (sizeBytes: 0, isDirectory: true, expected: ''),
        (sizeBytes: 500, isDirectory: false, expected: '500 B'),
        (sizeBytes: 1024, isDirectory: false, expected: '1.0 KB'),
        (sizeBytes: 1536, isDirectory: false, expected: '1.5 KB'),
        (sizeBytes: 1048576, isDirectory: false, expected: '1.0 MB'),
        (sizeBytes: 1073741824, isDirectory: false, expected: '1.00 GB'),
        (sizeBytes: 0, isDirectory: false, expected: ''),
      ];

      for (final (:sizeBytes, :isDirectory, :expected) in cases) {
        final item = FileItem(
          name: 'test',
          isDirectory: isDirectory,
          sizeBytes: sizeBytes,
          relativePath: '/test',
        );
        expect(item.formattedSize, expected, reason: 'size=$sizeBytes');
      }
    });
  });
}
