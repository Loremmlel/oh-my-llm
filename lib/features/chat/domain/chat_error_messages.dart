/// 聊天模块错误消息常量。
///
/// 集中管理错误提示字符串，避免散落多处导致文案不一致。
class ChatErrorMessages {
  const ChatErrorMessages._();

  /// 当前请求进行中，禁止并发操作
  static const busy = '当前仍有请求在进行，请稍后再试。';

  /// 所选检查点与当前分支不兼容
  static const incompatibleCheckpoint = '所选检查点与当前分支不兼容，请重新选择。';

  /// 没有可用于创建检查点的新上下文
  static const noCheckpointContext = '当前没有可用于创建检查点的新上下文。';

  /// 无法重算：没有可用模型
  static const noModelConfigForRecalc = '无法重算：当前对话没有可用模型，请先检查模型设置。';

  /// 无法重试：没有可用模型
  static const noModelConfigForRetry = '无法重试：当前对话没有可用模型，请先检查模型设置。';

  /// 只能重试最新的模型回复
  static const retryOnlyLatest = '只能重试当前对话中的最新模型回复。';

  /// 模型返回了空回复
  static const emptyReply = '[EMPTY] 模型返回了空回复，请重试';

  /// 请求未返回有效内容
  static const noValidContent = '[ERR] 请求未返回有效内容，请检查网络或重试';
}
