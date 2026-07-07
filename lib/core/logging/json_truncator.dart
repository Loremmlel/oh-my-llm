import 'package:characters/characters.dart';

/// 对 JSON 树中所有 String 值做长度截断，保留完整结构。

/// 日志字符串截断默认阈值（字符数）。
const int defaultMaxLogValueLength = 500;

/// 递归遍历 JSON-like Dart 对象，将所有超过 [maxLength] 的字符串值截断。
///
/// 处理规则：
/// - null → 返回 null
/// - String → 长度 > [maxLength] 时截断并追加 `...[truncated]`
/// - Map → 递归处理所有 value
/// - List → 递归处理所有元素
/// - 其他类型（int/bool/double 等）→ 原样返回
///
/// 截断以 Unicode 字符（grapheme cluster）为单位，避免在 surrogate pair
/// 中间切断导致产出含孤立代理对的无效字符串。
Object? truncateJsonValues(
  Object? input, {
  int maxLength = defaultMaxLogValueLength,
}) {
  if (input == null) {
    return null;
  }
  if (input is Map) {
    return input.map((key, value) {
      return MapEntry(key.toString(), truncateJsonValues(value, maxLength: maxLength));
    });
  }
  if (input is List) {
    return input.map((e) => truncateJsonValues(e, maxLength: maxLength)).toList(growable: false);
  }
  if (input is String) {
    return _truncateString(input, maxLength);
  }
  return input;
}

/// 按 grapheme cluster 截断字符串，避免切断 surrogate pair。
String _truncateString(String input, int maxLength) {
  final characters = input.characters;
  if (characters.length <= maxLength) {
    return input;
  }
  return '${characters.take(maxLength).toString()}...[truncated]';
}
