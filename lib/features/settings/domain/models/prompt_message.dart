import 'package:equatable/equatable.dart';

import 'prompt_message_placement.dart';
import 'prompt_message_role.dart';

String buildPresetPromptMessageFallbackTitle({
  required PromptMessageRole role,
  required PromptMessagePlacement placement,
  required int sequence,
}) {
  final placementLabel = switch (placement) {
    PromptMessagePlacement.before => '前置',
    PromptMessagePlacement.after => '后置',
  };
  return '$placementLabel${role.apiValue}$sequence';
}

/// Prompt 模板中的一条附加消息。
class PromptMessage extends Equatable {
  const PromptMessage({
    required this.id,
    required this.role,
    required this.content,
    this.title = '',
    this.placement = PromptMessagePlacement.before,
  });

  final String id;
  final PromptMessageRole role;
  final String content;
  final String title;
  final PromptMessagePlacement placement;

  /// 复制消息，并允许覆盖常用字段。
  PromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    String? content,
    String? title,
    PromptMessagePlacement? placement,
  }) {
    return PromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      title: title ?? this.title,
      placement: placement ?? this.placement,
    );
  }

  /// 将消息序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.apiValue,
      'title': title,
      'content': content,
      'placement': placement.apiValue,
    };
  }

  /// 从 JSON 反序列化消息。
  factory PromptMessage.fromJson(
    Map<String, dynamic> json, {
    String? fallbackTitle,
  }) {
    return PromptMessage(
      id: json['id'] as String,
      role: PromptMessageRole.fromApiValue(json['role'] as String),
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : (fallbackTitle ?? ''),
      content: json['content'] as String,
      placement: PromptMessagePlacement.fromApiValue(
        (json['placement'] as String?) ??
            PromptMessagePlacement.before.apiValue,
      ),
    );
  }

  @override
  List<Object> get props => [id, role, title, content, placement];
}
