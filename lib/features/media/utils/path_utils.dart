import '../domain/models/media_server_info.dart';

/// 对媒体路径的每段进行 URI 编码，以支持中文等非 ASCII 字符。
///
/// 根路径 `/` 返回空字符串。
String encodeMediaPath(String path) {
  if (path == '/') return '';
  return path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
}

/// 验证并规范化媒体路由的 path 参数。
///
/// 返回 null 表示参数缺失或非法；否则返回以 `/` 开头的规范化路径。
/// 只验证 route contract，不做文件系统访问。
String? normalizeMediaRoutePath(String? rawPath) {
  final trimmed = rawPath?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('/')) return null;
  final segments = trimmed
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return null;
  if (segments.any((s) => s == '.' || s == '..')) return null;
  return '/${segments.join('/')}';
}

/// 使用可信 server 与相对路径构建媒体资源 URL。
///
/// 路径段只编码一次；调用方必须传入已校验的 relativePath。
String buildMediaResourceUrl(
  MediaServerInfo server,
  String type,
  String relativePath,
) {
  return 'http://${server.ip}:${server.httpPort}/api/media/$type/${encodeMediaPath(relativePath)}';
}
