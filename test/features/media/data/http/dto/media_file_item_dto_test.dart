import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/data/http/dto/media_file_item_dto.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';

void main() {
  group('MediaFileItemDto 协议序列化', () {
    test('file JSON remains protocol compatible', () {
      const item = FileItem(
        name: 'test.mp4',
        isDirectory: false,
        sizeBytes: 1024,
        relativePath: '/test.mp4',
        lastModified: 1712345678,
        mimeType: 'video/mp4',
        hasThumbnail: true,
      );
      final json = MediaFileItemDto.fromDomain(item).toJson();
      expect(json, {
        'type': 'file',
        'name': 'test.mp4',
        'relativePath': '/test.mp4',
        'size': 1024,
        'lastModified': 1712345678,
        'mimeType': 'video/mp4',
        'thumbnailUrl': '/api/media/thumbnail/test.mp4',
      });
    });

    test('directory omits file-only keys', () {
      final json = MediaFileItemDto.fromDomain(
        const FileItem(
          name: 'subdir',
          isDirectory: true,
          sizeBytes: 0,
          relativePath: '/subdir',
        ),
      ).toJson();
      expect(json.containsKey('mimeType'), isFalse);
      expect(json.containsKey('thumbnailUrl'), isFalse);
    });

    test('非缩略图文件不输出 thumbnailUrl', () {
      final json = MediaFileItemDto.fromDomain(
        const FileItem(
          name: 'notes.txt',
          isDirectory: false,
          sizeBytes: 10,
          relativePath: '/notes.txt',
        ),
      ).toJson();
      expect(json.containsKey('thumbnailUrl'), isFalse);
    });
  });

  group('MediaFileItemDto.fromJson', () {
    test('缺失字段使用 legacy 默认值', () {
      final json = {'type': 'file', 'name': 'a.mp4', 'relativePath': '/a.mp4'};
      final dto = MediaFileItemDto.fromJson(json);
      expect(dto.item.sizeBytes, 0);
      expect(dto.item.lastModified, 0);
      expect(dto.item.mimeType, isNull);
      expect(dto.thumbnailUrl, isNull);
      expect(dto.item.hasThumbnail, isFalse);
      expect(dto.toDomain().hasThumbnail, isFalse);
    });

    test('thumbnailUrl 存在时推导 hasThumbnail', () {
      final dto = MediaFileItemDto.fromJson({
        'type': 'file',
        'name': 'cat.mp4',
        'relativePath': '/cat.mp4',
        'thumbnailUrl': '/api/media/thumbnail/cat.mp4',
      });
      expect(dto.item.hasThumbnail, isTrue);
      expect(dto.thumbnailUrl, '/api/media/thumbnail/cat.mp4');
    });

    test('缺失必填字段解码失败', () {
      expect(
        () => MediaFileItemDto.fromJson(<String, dynamic>{
          'type': 'file',
          'relativePath': '/a.mp4',
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MediaFileItemDto.fromJson(<String, dynamic>{
          'type': 'file',
          'name': 'a.mp4',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('MediaFileItemDto.toDomain', () {
    test('hasThumbnail 从 thumbnailUrl 反推，domain 不携带端点', () {
      final dto = MediaFileItemDto.fromDomain(
        const FileItem(
          name: 'a.jpg',
          isDirectory: false,
          sizeBytes: 1,
          relativePath: '/a.jpg',
          hasThumbnail: true,
        ),
      );
      final domain = dto.toDomain();
      expect(domain.hasThumbnail, isTrue);
    });
  });

  group('MediaFileItemDto.listFromJson', () {
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
      final dtos = MediaFileItemDto.listFromJson(json);
      expect(dtos.length, 2);
      expect(dtos[0].item.isDirectory, isTrue);
      expect(dtos[1].item.isDirectory, isFalse);
    });
  });
}
