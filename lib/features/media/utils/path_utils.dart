/// 验证并规范化媒体路由的 path 参数。
///
/// 返回 null 表示参数缺失或非法；否则返回以 `/` 开头的规范化路径。
/// 只验证 route contract，不做文件系统访问。
/// URL 路径的拼接由 data 层媒体库独占，本文件不再提供任何 URL 构建函数。
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
