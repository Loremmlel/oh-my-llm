/// LLM 生成 API 协议，服务商配置与聊天路由共享的最小纯 Dart 类型。
///
/// 协议属于服务商：其下全部模型继承同一协议。持久化与传输一律使用
/// [storageValue]，展示层使用 [displayName]。
enum LlmApiProtocol {
  chatCompletions('chatCompletions', 'Chat Completions'),
  responses('responses', 'Responses'),
  anthropic('anthropic', 'Anthropic');

  const LlmApiProtocol(this.storageValue, this.displayName);

  /// 持久化 / JSON 中的稳定字符串值，与枚举名一致。
  final String storageValue;

  /// 展示名，供设置界面等人类可读场景使用。
  final String displayName;

  /// 从存储字符串解析协议。
  ///
  /// 未知值必须失败（[FormatException]），不允许把拼写错误或未来协议
  /// 静默降级为 Chat Completions；兼容默认值只由各实体 `fromJson` 的
  /// 「字段缺失」分支承担。
  static LlmApiProtocol fromStorageValue(String value) {
    return LlmApiProtocol.values.firstWhere(
      (protocol) => protocol.storageValue == value,
      orElse: () => throw FormatException('未知 LLM API 协议：$value'),
    );
  }
}
