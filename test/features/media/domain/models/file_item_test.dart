import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

void main() {
  group('FileItem.toJson', () {
    test('文件夹不含 mimeType 和 thumbnailUrl', () {
      const item = FileItem(
        name: 'subdir',
        isDirectory: true,
        sizeBytes: 0,
        relativePath: '/subdir',
      );
      final json = item.toJson();
      expect(json['type'], 'directory');
      expect(json.containsKey('mimeType'), isFalse);
      expect(json.containsKey('thumbnailUrl'), isFalse);
    });

    test('文件包含 mimeType 和 thumbnailUrl', () {
      const item = FileItem(
        name: 'test.mp4',
        isDirectory: false,
        sizeBytes: 1024,
        relativePath: '/test.mp4',
        lastModified: 1712345678,
        mimeType: 'video/mp4',
        thumbnailUrl: '/api/media/thumbnail/test.mp4',
      );
      final json = item.toJson();
      expect(json['type'], 'file');
      expect(json['name'], 'test.mp4');
      expect(json['size'], 1024);
      expect(json['mimeType'], 'video/mp4');
      expect(json['thumbnailUrl'], '/api/media/thumbnail/test.mp4');
    });

    test('文件 mimeType 为 null 时不输出该字段', () {
      const item = FileItem(
        name: 'doc.txt',
        isDirectory: false,
        sizeBytes: 50,
        relativePath: '/doc.txt',
      );
      final json = item.toJson();
      expect(json.containsKey('mimeType'), isFalse);
      expect(json.containsKey('thumbnailUrl'), isFalse);
    });
  });

  group('FileItem.fromJson', () {
    test('正确反序列化文件', () {
      final json = {
        'type': 'file',
        'name': 'cat.mp4',
        'relativePath': '/sister/video/cat.mp4',
        'size': 123,
        'lastModified': 1712345678,
        'mimeType': 'video/mp4',
        'thumbnailUrl': '/api/media/thumbnail/sister/video/cat.mp4',
      };
      final item = FileItem.fromJson(json);
      expect(item.name, 'cat.mp4');
      expect(item.isDirectory, isFalse);
      expect(item.sizeBytes, 123);
      expect(item.relativePath, '/sister/video/cat.mp4');
      expect(item.lastModified, 1712345678);
      expect(item.mimeType, 'video/mp4');
      expect(item.thumbnailUrl, '/api/media/thumbnail/sister/video/cat.mp4');
    });

    test('正确反序列化文件夹', () {
      final json = {
        'type': 'directory',
        'name': 'video',
        'relativePath': '/sister/video',
        'size': 0,
        'lastModified': 0,
      };
      final item = FileItem.fromJson(json);
      expect(item.isDirectory, isTrue);
      expect(item.mimeType, isNull);
      expect(item.thumbnailUrl, isNull);
    });

    test('缺失字段使用默认值', () {
      final json = {
        'type': 'file',
        'name': 'a.mp4',
        'relativePath': '/a.mp4',
      };
      final item = FileItem.fromJson(json);
      expect(item.sizeBytes, 0);
      expect(item.lastModified, 0);
      expect(item.mimeType, isNull);
      expect(item.thumbnailUrl, isNull);
    });
  });

  group('FileItem.listFromJson', () {
    test('列表反序列化', () {
      final json = jsonEncode([
        {'type': 'directory', 'name': 'sub', 'relativePath': '/sub', 'size': 0, 'lastModified': 0},
        {'type': 'file', 'name': 'a.mp4', 'relativePath': '/a.mp4', 'size': 100, 'lastModified': 100},
      ]);
      final items = FileItem.listFromJson(json);
      expect(items.length, 2);
      expect(items[0].isDirectory, isTrue);
      expect(items[1].isDirectory, isFalse);
    });
  });

  group('FileItem.formattedSize', () {
    const cases = [
      (sizeBytes: 0, isDirectory: true, expected: ''),
      (sizeBytes: 500, isDirectory: false, expected: '500 B'),
      (sizeBytes: 1024, isDirectory: false, expected: '1.0 KB'),
      (sizeBytes: 1536, isDirectory: false, expected: '1.5 KB'),
      (sizeBytes: 1048576, isDirectory: false, expected: '1.0 MB'),
      (sizeBytes: 1073741824, isDirectory: false, expected: '1.00 GB'),
      (sizeBytes: 0, isDirectory: false, expected: ''),
    ];

    for (final c in cases) {
      test('${c.sizeBytes} bytes, isDirectory=${c.isDirectory} → "${c.expected}"', () {
        final item = FileItem(
          name: 'test',
          isDirectory: c.isDirectory,
          sizeBytes: c.sizeBytes,
          relativePath: '/test',
        );
        expect(item.formattedSize, c.expected);
      });
    }
  });
}
