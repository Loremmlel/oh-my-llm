import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'prompt_message.dart';
import 'prompt_message_placement.dart';
import 'prompt_message_role.dart';

export 'prompt_message.dart';
export 'prompt_message_placement.dart';
export 'prompt_message_role.dart';

const defaultSystemPromptTitle = 'system';

/// 可复用的 Prompt 模板，使用统一消息列表表示 system / user / assistant 条目。
class PresetPrompt extends Equatable {
  const PresetPrompt({
    required this.id,
    required this.name,
    required this.messages,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<PromptMessage> messages;
  final DateTime updatedAt;

  Iterable<PromptMessage> messagesForPlacement(
    PromptMessagePlacement placement,
  ) {
    return messages.where((message) => message.placement == placement);
  }

  /// 复制模板，并允许覆盖标题、消息和更新时间。
  PresetPrompt copyWith({
    String? id,
    String? name,
    List<PromptMessage>? messages,
    DateTime? updatedAt,
  }) {
    return PresetPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 将模板序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'messages': messages.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化模板。
  factory PresetPrompt.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    final messages = _deserializePromptMessages(rawMessages);
    final hasSystemMessages = messages.any(
      (message) => message.role == PromptMessageRole.system,
    );

    List<PromptMessage> effectiveMessages = messages;
    if (!hasSystemMessages) {
      final legacySystemPrompt =
          (json['systemPrompt'] as String?)?.trim() ?? '';
      if (legacySystemPrompt.isNotEmpty) {
        final title =
            (json['systemPromptTitle'] as String?)?.trim().isNotEmpty == true
                ? json['systemPromptTitle'] as String
                : defaultSystemPromptTitle;
        effectiveMessages = [
          PromptMessage(
            id: '_legacy-system-message',
            role: PromptMessageRole.system,
            title: title,
            content: legacySystemPrompt,
            placement: PromptMessagePlacement.before,
          ),
          ...messages,
        ];
      }
    }

    return PresetPrompt(
      id: json['id'] as String,
      name: json['name'] as String,
      messages: effectiveMessages,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 返回模板内容的摘要，便于列表页快速浏览。
  String get summary {
    if (messages.isEmpty) {
      return '暂无模板消息';
    }

    return '共 ${messages.length} 条消息';
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, name, messages, updatedAt];
}

List<PromptMessage> _deserializePromptMessages(List<dynamic> rawMessages) {
  final messageCounters = <String, int>{};
  return rawMessages
      .map((item) {
        final messageJson = Map<String, dynamic>.from(item as Map);
        final role = PromptMessageRole.fromApiValue(
          messageJson['role'] as String,
        );
        final placement = PromptMessagePlacement.fromApiValue(
          (messageJson['placement'] as String?) ??
              PromptMessagePlacement.before.apiValue,
        );
        final counterKey = '${placement.apiValue}:${role.apiValue}';
        final nextSequence = (messageCounters[counterKey] ?? 0) + 1;
        messageCounters[counterKey] = nextSequence;
        return PromptMessage.fromJson(
          messageJson,
          fallbackTitle: buildPresetPromptMessageFallbackTitle(
            role: role,
            placement: placement,
            sequence: nextSequence,
          ),
        );
      })
      .toList(growable: false);
}
