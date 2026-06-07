import 'dart:convert';

/// 媒体文件系统中的文件/文件夹统一抽象。
///
/// [relativePath] 是唯一标识，客户端禁止依赖文件名作为唯一标识。
class FileItem {
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final String relativePath;

  const FileItem({
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.relativePath,
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

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'isDirectory': isDirectory,
      'sizeBytes': sizeBytes,
      'relativePath': relativePath,
    };
  }

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] as String,
      isDirectory: json['isDirectory'] as bool,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      relativePath: json['relativePath'] as String,
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
