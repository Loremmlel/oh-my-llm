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
