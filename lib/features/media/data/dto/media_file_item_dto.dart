import 'dart:convert';

import '../../domain/models/file_item.dart';

/// `/api/media/list` 协议列表项的 data 层 DTO。
///
/// 负责 wire 字段的解析与编码，并在此处推导缩略图端点
/// （`/api/media/thumbnail...`），不让端点信息下沉到 domain；
/// domain 只持有传输无关的 [FileItem.hasThumbnail] 信号。
///
/// 编码语义与 legacy `FileItem.toJson` 逐字节兼容：
/// 缺失 `size`/`lastModified` 记为 0，缺失可选字段记为 null/false，
/// 缺失必填 `name`/`relativePath` 仍是解码失败。
final class MediaFileItemDto {
  const MediaFileItemDto({required this.item, required this.thumbnailUrl});

  final FileItem item;
  final String? thumbnailUrl;

  factory MediaFileItemDto.fromDomain(FileItem item) => MediaFileItemDto(
    item: item,
    thumbnailUrl: item.hasThumbnail
        ? '/api/media/thumbnail${item.relativePath}'
        : null,
  );

  /// 还原为传输无关的 domain 模型：仅把 [hasThumbnail] 从
  /// [thumbnailUrl] 反推，不把端点路径写回 domain。
  FileItem toDomain() => FileItem(
    name: item.name,
    isDirectory: item.isDirectory,
    sizeBytes: item.sizeBytes,
    relativePath: item.relativePath,
    lastModified: item.lastModified,
    mimeType: item.mimeType,
    hasThumbnail: thumbnailUrl != null,
  );

  factory MediaFileItemDto.fromJson(Map<String, dynamic> json) {
    return MediaFileItemDto(
      item: FileItem(
        name: json['name'] as String,
        isDirectory: json['type'] == 'directory',
        sizeBytes: json['size'] as int? ?? 0,
        relativePath: json['relativePath'] as String,
        lastModified: json['lastModified'] as int? ?? 0,
        mimeType: json['mimeType'] as String?,
        hasThumbnail: json['thumbnailUrl'] != null,
      ),
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': item.isDirectory ? 'directory' : 'file',
      'name': item.name,
      'relativePath': item.relativePath,
      'size': item.sizeBytes,
      'lastModified': item.lastModified,
    };
    if (!item.isDirectory) {
      if (item.mimeType != null) json['mimeType'] = item.mimeType;
      if (thumbnailUrl != null) json['thumbnailUrl'] = thumbnailUrl;
    }
    return json;
  }

  static List<MediaFileItemDto> listFromJson(String jsonString) {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return list
        .map((e) => MediaFileItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
