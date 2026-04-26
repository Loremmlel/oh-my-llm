import 'package:equatable/equatable.dart';

enum PromptMessageRole {
  user('user'),
  assistant('assistant');

  const PromptMessageRole(this.apiValue);

  final String apiValue;
}

class PromptMessage extends Equatable {
  const PromptMessage({
    required this.id,
    required this.role,
    required this.content,
  });

  final String id;
  final PromptMessageRole role;
  final String content;

  PromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    String? content,
  }) {
    return PromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
    );
  }

  @override
  List<Object> get props => [id, role, content];
}

class PromptTemplate extends Equatable {
  const PromptTemplate({
    required this.id,
    required this.name,
    required this.systemPrompt,
    required this.messages,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String systemPrompt;
  final List<PromptMessage> messages;
  final DateTime updatedAt;

  PromptTemplate copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    List<PromptMessage>? messages,
    DateTime? updatedAt,
  }) {
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object> get props => [id, name, systemPrompt, messages, updatedAt];
}
