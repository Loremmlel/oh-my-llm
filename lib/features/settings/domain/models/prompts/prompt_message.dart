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
    PromptMessagePlacement.beforeLatestInput => '最新输入前',
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
    this.enabled = true,
    this.sourceIdentifier,
    this.importInsertionOrder,
  });

  final String id;
  final PromptMessageRole role;
  final String content;
  final String title;
  final PromptMessagePlacement placement;
  final bool enabled;
  final String? sourceIdentifier;
  final int? importInsertionOrder;

  /// 复制消息，并允许覆盖常用字段。
  PromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    String? content,
    String? title,
    PromptMessagePlacement? placement,
    bool? enabled,
    String? sourceIdentifier,
    int? importInsertionOrder,
    bool clearImportInsertionOrder = false,
  }) {
    return PromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      title: title ?? this.title,
      placement: placement ?? this.placement,
      enabled: enabled ?? this.enabled,
      sourceIdentifier: sourceIdentifier ?? this.sourceIdentifier,
      importInsertionOrder: clearImportInsertionOrder
          ? null
          : importInsertionOrder ?? this.importInsertionOrder,
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
      'enabled': enabled,
      if (sourceIdentifier != null) 'sourceIdentifier': sourceIdentifier,
      if (importInsertionOrder != null)
        'importInsertionOrder': importInsertionOrder,
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
      title: json['title'] as String? ?? fallbackTitle ?? '',
      content: json['content'] as String,
      placement: PromptMessagePlacement.fromApiValue(
        (json['placement'] as String?) ??
            PromptMessagePlacement.before.apiValue,
      ),
      enabled: (json['enabled'] as bool?) ?? true,
      sourceIdentifier: json['sourceIdentifier'] as String?,
      importInsertionOrder: json['importInsertionOrder'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    role,
    title,
    content,
    placement,
    enabled,
    sourceIdentifier,
    importInsertionOrder,
  ];
}
