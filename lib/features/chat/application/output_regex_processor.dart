import '../../settings/domain/models/output_processing_settings.dart';

/// 对模型输出正文应用一组正则规则（过滤或替换）。
///
/// - 按 [OutputRegexRule.order] 升序链式应用，前一条的结果作为后一条的输入。
/// - 跳过禁用规则与空表达式规则。
/// - 无效表达式静默跳过，避免因用户配置错误中断输出。
/// - 编译后的 [RegExp] 按表达式字符串缓存，避免流式每次 flush 重编译。
String applyOutputRegexRules(String content, List<OutputRegexRule> rules) {
  if (content.isEmpty || rules.isEmpty) {
    return content;
  }

  final ordered = [...rules]..sort((a, b) => a.order.compareTo(b.order));

  var result = content;
  for (final rule in ordered) {
    if (!rule.enabled || rule.pattern.isEmpty) {
      continue;
    }
    final regExp = _compile(rule.pattern);
    if (regExp == null) {
      continue;
    }
    result = result.replaceAll(regExp, rule.replacement);
  }
  return result;
}

final Map<String, RegExp?> _regExpCache = {};

/// 缓存上限：规则数量有限，超限时清空重建，避免无界增长。
const _maxRegExpCacheSize = 256;

RegExp? _compile(String pattern) {
  if (_regExpCache.containsKey(pattern)) {
    return _regExpCache[pattern];
  }
  if (_regExpCache.length >= _maxRegExpCacheSize) {
    _regExpCache.clear();
  }
  RegExp? compiled;
  try {
    compiled = RegExp(pattern, unicode: true);
  } on FormatException {
    compiled = null;
  }
  _regExpCache[pattern] = compiled;
  return compiled;
}
