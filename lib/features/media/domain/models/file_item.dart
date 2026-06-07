import 'dart:convert';

/// 媒体文件系统中的文件/文件夹统一抽象。
///
/// [relativePath] 是唯一标识，客户端禁止依赖文件名作为唯一标识。
class FileItem {
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final String relativePath;
  /// 文件最后修改时间（毫秒时间戳）；文件夹为 0。
  final int lastModified;
  /// MIME 类型（如 "video/mp4"）；文件夹为 null。
  final String? mimeType;
  /// 缩略图相对 API 路径（如 "/api/media/thumbnail/sister/cat.mp4"）；
  /// 文件夹和非图片/视频文件为 null。
  /// 此字段存储未编码的原始路径——客户端负责在发起 HTTP 请求前对路径段进行 URI 编码。
  final String? thumbnailUrl;

  const FileItem({
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.relativePath,
    this.lastModified = 0,
    this.mimeType,
    this.thumbnailUrl,
  });

  /// 人类可读的文件大小，文件夹返回空字符串。
  String get formattedSize {
    if (isDirectory || sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 序列化为 PRD 规范的 JSON 格式。
  ///
  /// 输出示例：
  /// ```json
  /// {"type":"directory","name":"video","relativePath":"/sister/video","size":0,"lastModified":0}
  /// {"type":"file","name":"cat.mp4","relativePath":"/sister/video/cat.mp4","size":123,"lastModified":1712345678,"mimeType":"video/mp4","thumbnailUrl":"/api/media/thumbnail/sister/video/cat.mp4"}
  /// ```
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': isDirectory ? 'directory' : 'file',
      'name': name,
      'relativePath': relativePath,
      'size': sizeBytes,
      'lastModified': lastModified,
    };
    if (!isDirectory) {
      if (mimeType != null) json['mimeType'] = mimeType;
      if (thumbnailUrl != null) json['thumbnailUrl'] = thumbnailUrl;
    }
    return json;
  }

  /// 从 JSON 反序列化。
  ///
  /// 兼容旧格式（`isDirectory`/`sizeBytes`）和新格式（`type`/`size`）。
  factory FileItem.fromJson(Map<String, dynamic> json) {
    // 兼容新旧两种 type/isDirectory 字段
    final type = json['type'] as String?;
    final isDir = type != null
        ? type == 'directory'
        : (json['isDirectory'] as bool? ?? false);

    // 兼容新旧两种 size/sizeBytes 字段
    final size = (json['size'] ?? json['sizeBytes']) as int? ?? 0;

    return FileItem(
      name: json['name'] as String,
      isDirectory: isDir,
      sizeBytes: size,
      relativePath: json['relativePath'] as String,
      lastModified: json['lastModified'] as int? ?? 0,
      mimeType: json['mimeType'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  static List<FileItem> listFromJson(String jsonString) {
    final list = jsonDecode(jsonString) as List<dynamic>;
    return list
        .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() =>
      'FileItem(name: $name, isDir: $isDirectory, path: $relativePath)';
}
