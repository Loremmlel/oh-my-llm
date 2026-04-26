import 'dart:convert';

import 'package:equatable/equatable.dart';

enum PromptMessageRole {
  user('user'),
  assistant('assistant');

  const PromptMessageRole(this.apiValue);

  final String apiValue;

  String get label => switch (this) {
        PromptMessageRole.user => 'User',
        PromptMessageRole.assistant => 'Assistant',
      };

  static PromptMessageRole fromApiValue(String value) {
    return PromptMessageRole.values.firstWhere(
      (role) => role.apiValue == value,
    );
  }
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.apiValue,
      'content': content,
    };
  }

  factory PromptMessage.fromJson(Map<String, dynamic> json) {
    return PromptMessage(
      id: json['id'] as String,
      role: PromptMessageRole.fromApiValue(json['role'] as String),
      content: json['content'] as String,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      'messages': messages.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];

    return PromptTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      systemPrompt: json['systemPrompt'] as String,
      messages: rawMessages
          .map((item) => PromptMessage.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String get summary {
    if (messages.isEmpty) {
      return '仅包含 system 指令';
    }

    return '1 条 system 指令 + ${messages.length} 条附加消息';
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, name, systemPrompt, messages, updatedAt];
}
