/// Prompt 模板附加消息在请求中的拼接位置。
enum PromptMessagePlacement {
  before('before'),
  after('after');

  const PromptMessagePlacement(this.apiValue);

  final String apiValue;

  /// 返回更适合界面展示的位置标签。
  String get label => switch (this) {
    PromptMessagePlacement.before => '前置',
    PromptMessagePlacement.after => '后置',
  };

  /// 从持久化字符串解析位置枚举。
  static PromptMessagePlacement fromApiValue(String value) {
    return PromptMessagePlacement.values.firstWhere(
      (placement) => placement.apiValue == value,
      orElse: () => PromptMessagePlacement.before,
    );
  }
}
