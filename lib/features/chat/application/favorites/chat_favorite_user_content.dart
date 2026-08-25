import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';

/// 解析收藏 draft 的 user 侧内容：在 assistant 之前反向找最近 user；
/// 前缀非空但无 user 时回退前缀第一条；assistant 位于索引 0 或不存在时
/// 返回空字符串。既有产品行为，不重新定义。
String resolveFavoriteUserContent(
  ChatConversation conversation,
  ChatMessage assistantMessage,
) {
  final messages = conversation.messages;
  final assistantIndex = messages.indexWhere(
    (m) => m.id == assistantMessage.id,
  );
  if (assistantIndex <= 0) return '';
  final prefix = messages.sublist(0, assistantIndex);
  final userMessage = prefix.lastWhere(
    (m) => m.role == ChatMessageRole.user,
    orElse: () => prefix.first,
  );
  return userMessage.content;
}
