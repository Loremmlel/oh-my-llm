import 'dart:convert';

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
    this.selectedModelId,
    this.selectedPromptTemplateId,
    this.reasoningEnabled = false,
    this.reasoningEffort = ReasoningEffort.medium,
  });

  final String id;
  final String? title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? selectedModelId;
  final String? selectedPromptTemplateId;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  bool get hasMessages => messages.isNotEmpty;

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
    String? selectedModelId,
    String? selectedPromptTemplateId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool clearSelectedModelId = false,
    bool clearSelectedPromptTemplateId = false,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedModelId: clearSelectedModelId
          ? null
          : selectedModelId ?? this.selectedModelId,
      selectedPromptTemplateId: clearSelectedPromptTemplateId
          ? null
          : selectedPromptTemplateId ?? this.selectedPromptTemplateId,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((message) => message.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'selectedModelId': selectedModelId,
      'selectedPromptTemplateId': selectedPromptTemplateId,
      'reasoningEnabled': reasoningEnabled,
      'reasoningEffort': reasoningEffort.apiValue,
    };
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];

    return ChatConversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      messages: rawMessages
          .map((message) {
            return ChatMessage.fromJson(
              Map<String, dynamic>.from(message as Map),
            );
          })
          .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      selectedModelId: json['selectedModelId'] as String?,
      selectedPromptTemplateId: json['selectedPromptTemplateId'] as String?,
      reasoningEnabled: json['reasoningEnabled'] as bool? ?? false,
      reasoningEffort: ReasoningEffort.values.firstWhere(
        (effort) => effort.apiValue == json['reasoningEffort'],
        orElse: () => ReasoningEffort.medium,
      ),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object?> get props => [
        id,
        title,
        messages,
        createdAt,
        updatedAt,
        selectedModelId,
        selectedPromptTemplateId,
        reasoningEnabled,
        reasoningEffort,
      ];
}
