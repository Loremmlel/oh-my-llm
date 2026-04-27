import '../../domain/models/chat_message.dart';

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
