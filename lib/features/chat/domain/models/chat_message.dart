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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.apiValue,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: ChatMessageRole.values.firstWhere(
        (role) => role.apiValue == json['role'],
      ),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  List<Object> get props => [id, role, content, createdAt, isStreaming];
}
