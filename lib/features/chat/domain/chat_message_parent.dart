import 'models/chat_conversation.dart';
import 'models/chat_message.dart';

/// [ChatMessage] 父 ID 便捷扩展。
extension ChatMessageParent on ChatMessage {
  /// 返回消息的有效父 ID：自身 parentId 优先，否则回退到会话根 ID。
  String get effectiveParentId => parentId ?? rootConversationParentId;
}
