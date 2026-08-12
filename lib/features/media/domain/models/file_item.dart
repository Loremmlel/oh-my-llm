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

  /// 是否具备缩略图（传输无关的信号）。
  ///
  /// 由 data 层 DTO 从 wire 的 `thumbnailUrl` 反推并推导端点，
  /// domain 自身不再负责拼接端点路径。
  final bool hasThumbnail;

  const FileItem({
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.relativePath,
    this.lastModified = 0,
    this.mimeType,
    this.hasThumbnail = false,
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

  @override
  String toString() =>
      'FileItem(name: $name, isDir: $isDirectory, path: $relativePath)';
}
