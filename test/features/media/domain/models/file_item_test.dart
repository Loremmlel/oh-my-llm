import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

void main() {
  group('FileItem 序列化往返', () {
    test('文件：可选键存在且反序列化还原', () {
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
      expect(json.containsKey('mimeType'), isTrue);
      expect(json['mimeType'], 'video/mp4');
      expect(json.containsKey('thumbnailUrl'), isTrue);
      expect(json['thumbnailUrl'], '/api/media/thumbnail/test.mp4');

      final decoded = FileItem.fromJson(json);
      expect(decoded.name, 'test.mp4');
      expect(decoded.isDirectory, isFalse);
      expect(decoded.sizeBytes, 1024);
      expect(decoded.relativePath, '/test.mp4');
      expect(decoded.lastModified, 1712345678);
      expect(decoded.mimeType, 'video/mp4');
      expect(decoded.thumbnailUrl, '/api/media/thumbnail/test.mp4');
      // wire 的 thumbnailUrl 反推出传输无关信号
      expect(decoded.hasThumbnail, isTrue);
    });

    test('文件夹：可选键不输出且反序列化还原', () {
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

      final decoded = FileItem.fromJson(json);
      expect(decoded.isDirectory, isTrue);
      expect(decoded.mimeType, isNull);
      expect(decoded.thumbnailUrl, isNull);
      expect(decoded.hasThumbnail, isFalse);
    });
  });

  group('FileItem.fromJson', () {
    test('缺失字段使用默认值', () {
      final json = {'type': 'file', 'name': 'a.mp4', 'relativePath': '/a.mp4'};
      final item = FileItem.fromJson(json);
      expect(item.sizeBytes, 0);
      expect(item.lastModified, 0);
      expect(item.mimeType, isNull);
      expect(item.thumbnailUrl, isNull);
      expect(item.hasThumbnail, isFalse);
    });

    test('thumbnailUrl 存在时推导 hasThumbnail，旧 JSON 输出不变', () {
      final item = FileItem.fromJson({
        'type': 'file',
        'name': 'a.mp4',
        'relativePath': '/a.mp4',
        'thumbnailUrl': '/api/media/thumbnail/a.mp4',
      });
      expect(item.hasThumbnail, isTrue);
      // 旧序列化仍从 thumbnailUrl 输出 legacy 键
      expect(item.toJson()['thumbnailUrl'], '/api/media/thumbnail/a.mp4');
    });
  });

  group('FileItem.listFromJson', () {
    test('列表反序列化', () {
      final json = jsonEncode([
        {
          'type': 'directory',
          'name': 'sub',
          'relativePath': '/sub',
          'size': 0,
          'lastModified': 0,
        },
        {
          'type': 'file',
          'name': 'a.mp4',
          'relativePath': '/a.mp4',
          'size': 100,
          'lastModified': 100,
        },
      ]);
      final items = FileItem.listFromJson(json);
      expect(items.length, 2);
      expect(items[0].isDirectory, isTrue);
      expect(items[1].isDirectory, isFalse);
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
