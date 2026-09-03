import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

void main() {
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
