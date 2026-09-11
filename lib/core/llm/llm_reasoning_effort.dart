/// 模型推理强度枚举，保持与 API 的字符串值一致。
enum ReasoningEffort {
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh'),
  max('max');

  const ReasoningEffort(this.apiValue);

  final String apiValue;
}
