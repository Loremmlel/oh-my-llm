import 'dart:convert';

import 'package:equatable/equatable.dart';

/// 固定顺序提示词中的单个步骤。
class FixedPromptSequenceStep extends Equatable {
  const FixedPromptSequenceStep({required this.id, required this.content});

  final String id;
  final String content;

  /// 复制步骤并允许覆盖字段。
  FixedPromptSequenceStep copyWith({String? id, String? content}) {
    return FixedPromptSequenceStep(
      id: id ?? this.id,
      content: content ?? this.content,
    );
  }

  /// 将步骤序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {'id': id, 'content': content};
  }

  /// 从 JSON 反序列化步骤。
  factory FixedPromptSequenceStep.fromJson(Map<String, dynamic> json) {
    return FixedPromptSequenceStep(
      id: json['id'] as String,
      content: json['content'] as String,
    );
  }

  @override
  List<Object> get props => [id, content];
}

/// 供聊天页按顺序逐步发送的固定提示词序列。
class FixedPromptSequence extends Equatable {
  const FixedPromptSequence({
    required this.id,
    required this.name,
    required this.steps,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<FixedPromptSequenceStep> steps;
  final DateTime updatedAt;

  /// 复制序列并允许覆盖常用字段。
  FixedPromptSequence copyWith({
    String? id,
    String? name,
    List<FixedPromptSequenceStep>? steps,
    DateTime? updatedAt,
  }) {
    return FixedPromptSequence(
      id: id ?? this.id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 将序列序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'steps': steps.map((step) => step.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化序列。
  factory FixedPromptSequence.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];

    return FixedPromptSequence(
      id: json['id'] as String,
      name: json['name'] as String,
      steps: rawSteps
          .map(
            (item) => FixedPromptSequenceStep.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 返回便于列表快速浏览的摘要。
  String get summary {
    if (steps.isEmpty) {
      return '还没有步骤';
    }

    return '共 ${steps.length} 步';
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, name, steps, updatedAt];
}
