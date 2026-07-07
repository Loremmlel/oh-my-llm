import 'package:characters/characters.dart';

/// 把长文本截断为适合列表显示的摘要。
///
/// 先将换行替换为空格并去除首尾空白；空内容时返回 [emptyText]。
///
/// 截断以 Unicode 字符（grapheme cluster）为单位，避免在 surrogate pair
/// 中间切断导致产出含孤立代理对的无效字符串。
String summarizeText(
  String content, {
  int maxLength = 30,
  String emptyText = '',
}) {
  final normalized = content.trim().replaceAll('\n', ' ');
  if (normalized.isEmpty) return emptyText;
  final characters = normalized.characters;
  if (characters.length <= maxLength) return normalized;
  return '${characters.take(maxLength).toString()}...';
}
