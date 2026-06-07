/// 媒体文件扩展名与 MIME 类型共享常量与工具函数。
///
/// 供以下模块使用：
/// - [MediaFileTile] 图标选择
/// - [MediaBrowserTab] 点击导航判断
/// - [MediaImageHttpHandler] / [MediaVideoHttpHandler] Content-Type 设置
library;

/// 支持的图片扩展名（小写）。
const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// 支持的视频扩展名（小写）。
const videoExtensions = {'mp4', 'mkv', 'mov', 'avi', 'webm'};

/// 从文件名提取小写扩展名，无扩展名时返回空字符串。
String _extension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
}

/// 根据文件名扩展名判断是否为图片。
bool isImageFile(String name) => imageExtensions.contains(_extension(name));

/// 根据文件名扩展名判断是否为视频。
bool isVideoFile(String name) => videoExtensions.contains(_extension(name));

/// 根据文件名扩展名返回 MIME 类型（大小写不敏感）。
///
/// 未知扩展名返回 `application/octet-stream`。
String mimeTypeFromExtension(String fileName) {
  final ext = _extension(fileName);
  switch (ext) {
    // ── 图片 ──
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    // ── 视频 ──
    case 'mp4':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'mov':
      return 'video/quicktime';
    case 'avi':
      return 'video/x-msvideo';
    case 'webm':
      return 'video/webm';
    // ── 默认 ──
    default:
      return 'application/octet-stream';
  }
}
