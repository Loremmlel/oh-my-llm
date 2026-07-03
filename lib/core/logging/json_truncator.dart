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
    if (input.length > maxLength) {
      return '${input.substring(0, maxLength)}...[truncated]';
    }
    return input;
  }
  return input;
}
