import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

import 'chat_message.dart';

class ChatConversation extends Equatable {
  const ChatConversation({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.title,
  });

  final String id;
  final String? title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get resolvedTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }

    final firstUserMessage = messages.where((message) {
      return message.role == ChatMessageRole.user;
    }).firstOrNull;

    if (firstUserMessage == null || firstUserMessage.content.trim().isEmpty) {
      return '未命名对话';
    }

    final normalizedContent = firstUserMessage.content.trim();
    return normalizedContent.characters.take(15).toString();
  }

  ChatConversation copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, title, messages, createdAt, updatedAt];
}
