import 'package:equatable/equatable.dart';

enum ChatMessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const ChatMessageRole(this.apiValue);

  final String apiValue;
}

enum ReasoningEffort {
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh');

  const ReasoningEffort(this.apiValue);

  final String apiValue;
}

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isStreaming = false,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final DateTime createdAt;
  final bool isStreaming;

  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? content,
    DateTime? createdAt,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  @override
  List<Object> get props => [id, role, content, createdAt, isStreaming];
}
