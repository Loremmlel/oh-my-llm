/// Prompt 模板中附加消息的发送角色。
enum PromptMessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const PromptMessageRole(this.apiValue);

  final String apiValue;

  /// 返回更适合界面展示的角色标签。
  String get label => switch (this) {
    PromptMessageRole.system => 'System',
    PromptMessageRole.user => 'User',
    PromptMessageRole.assistant => 'Assistant',
  };

  /// 从 API 字符串值解析角色枚举。
  static PromptMessageRole fromApiValue(String value) {
    return PromptMessageRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => PromptMessageRole.user,
    );
  }
}
