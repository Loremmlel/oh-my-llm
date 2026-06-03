import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../../core/utils/text_formatting.dart';

/// 记忆总结提示词，用于为检查点生成不同风格的总结。
class MemoryPrompt extends Equatable {
  const MemoryPrompt({
    required this.id,
    required this.name,
    required this.content,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String content;
  final DateTime updatedAt;

  /// 返回便于列表快速浏览的摘要。
  String get summary =>
      summarizeText(content, maxLength: 36, emptyText: '内容为空');

  MemoryPrompt copyWith({
    String? id,
    String? name,
    String? content,
    DateTime? updatedAt,
  }) {
    return MemoryPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory MemoryPrompt.fromJson(Map<String, dynamic> json) {
    return MemoryPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, name, content, updatedAt];
}
