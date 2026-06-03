import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../../core/utils/text_formatting.dart';

/// 对话级检查点，保存某一阶段的记忆总结。
class ChatCheckpoint extends Equatable {
  const ChatCheckpoint({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.parentCheckpointId,
    this.coveredUntilMessageId,
    this.sourceMemoryPromptName = '',
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final String? parentCheckpointId;
  final String? coveredUntilMessageId;
  final String sourceMemoryPromptName;

  /// 返回用于列表预览的简短摘要。
  String get summary =>
      summarizeText(content, maxLength: 42, emptyText: '该检查点为空。');

  ChatCheckpoint copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    String? parentCheckpointId,
    String? coveredUntilMessageId,
    String? sourceMemoryPromptName,
  }) {
    return ChatCheckpoint(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      parentCheckpointId: parentCheckpointId ?? this.parentCheckpointId,
      coveredUntilMessageId: coveredUntilMessageId ?? this.coveredUntilMessageId,
      sourceMemoryPromptName:
          sourceMemoryPromptName ?? this.sourceMemoryPromptName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'parentCheckpointId': parentCheckpointId,
      'coveredUntilMessageId': coveredUntilMessageId,
      'sourceMemoryPromptName': sourceMemoryPromptName,
    };
  }

  factory ChatCheckpoint.fromJson(Map<String, dynamic> json) {
    return ChatCheckpoint(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      parentCheckpointId: json['parentCheckpointId'] as String?,
      coveredUntilMessageId: json['coveredUntilMessageId'] as String?,
      sourceMemoryPromptName: json['sourceMemoryPromptName'] as String? ?? '',
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object?> get props => [
    id,
    title,
    content,
    createdAt,
    parentCheckpointId,
    coveredUntilMessageId,
    sourceMemoryPromptName,
  ];
}
