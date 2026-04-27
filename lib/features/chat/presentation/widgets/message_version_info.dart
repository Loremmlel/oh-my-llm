import '../../domain/models/chat_message.dart';

/// 某条消息所在版本组的上下文信息。
class MessageVersionInfo {
  const MessageVersionInfo({
    required this.parentId,
    required this.currentIndex,
    required this.siblings,
  });

  final String parentId;
  final int currentIndex;
  final List<ChatMessage> siblings;
}
