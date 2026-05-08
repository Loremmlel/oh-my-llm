import '../domain/models/chat_message.dart';

/// 过滤/裁剪请求消息列表的策略抽象。
///
/// 每种实现对应一种过滤规则（按 ID 排除、截断上下文窗口等），
/// 可在不修改 [buildRequestMessages] / [buildCheckpointSummaryMessages]
/// 签名的前提下扩展新规则。
abstract class RequestMessageFilter {
  const RequestMessageFilter();

  List<ChatMessage> apply(List<ChatMessage> messages);

  /// 不做任何过滤，直接原样返回。
  static const passthrough = PassthroughMessageFilter();
}

/// 透传策略：不对消息列表做任何变更。
class PassthroughMessageFilter extends RequestMessageFilter {
  const PassthroughMessageFilter();

  @override
  List<ChatMessage> apply(List<ChatMessage> messages) =>
      List.unmodifiable(messages);
}

/// 按 ID 集合排除消息的过滤策略。
class ExcludeByIdMessageFilter extends RequestMessageFilter {
  const ExcludeByIdMessageFilter(this.excludedIds);

  final Set<String> excludedIds;

  @override
  List<ChatMessage> apply(List<ChatMessage> messages) {
    if (excludedIds.isEmpty) {
      return List.unmodifiable(messages);
    }
    return List.unmodifiable(
      messages
          .where((message) => !excludedIds.contains(message.id))
          .toList(growable: false),
    );
  }
}
