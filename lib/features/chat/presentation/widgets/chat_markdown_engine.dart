/// 聊天 Markdown 渲染内核。
enum ChatMarkdownEngine {
  /// 旧实现：flutter_markdown_plus。
  legacy,

  /// 新实现：flutter_smooth_markdown。
  smooth,
}

/// 当前启用的渲染内核。
///
/// 采用双实现切换策略，默认启用 smooth；
/// 如需紧急回滚，可临时切回 legacy。
const ChatMarkdownEngine kChatMarkdownEngine = ChatMarkdownEngine.smooth;
