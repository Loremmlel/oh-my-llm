/// 把长文本截断为适合列表显示的摘要。
///
/// 先将换行替换为空格并去除首尾空白；空内容时返回 [emptyText]。
String summarizeText(
  String content, {
  int maxLength = 30,
  String emptyText = '',
}) {
  final normalized = content.trim().replaceAll('\n', ' ');
  if (normalized.isEmpty) return emptyText;
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength)}...';
}
