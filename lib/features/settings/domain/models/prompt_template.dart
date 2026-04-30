import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Prompt 模板中附加消息的发送角色。
enum PromptMessageRole {
  user('user'),
  assistant('assistant');

  const PromptMessageRole(this.apiValue);

  final String apiValue;

  /// 返回更适合界面展示的角色标签。
  String get label => switch (this) {
    PromptMessageRole.user => 'User',
    PromptMessageRole.assistant => 'Assistant',
  };

  /// 从 API 字符串值解析角色枚举。
  static PromptMessageRole fromApiValue(String value) {
    return PromptMessageRole.values.firstWhere(
      (role) => role.apiValue == value,
    );
  }
}

/// Prompt 模板附加消息在请求中的拼接位置。
enum PromptMessagePlacement {
  before('before'),
  after('after');

  const PromptMessagePlacement(this.apiValue);

  final String apiValue;

  /// 返回更适合界面展示的位置标签。
  String get label => switch (this) {
    PromptMessagePlacement.before => '会话前',
    PromptMessagePlacement.after => '会话后',
  };

  /// 从持久化字符串解析位置枚举。
  static PromptMessagePlacement fromApiValue(String value) {
    return PromptMessagePlacement.values.firstWhere(
      (placement) => placement.apiValue == value,
      orElse: () => PromptMessagePlacement.before,
    );
  }
}

/// Prompt 模板中的一条附加消息。
class PromptMessage extends Equatable {
  const PromptMessage({
    required this.id,
    required this.role,
    required this.content,
    this.placement = PromptMessagePlacement.before,
  });

  final String id;
  final PromptMessageRole role;
  final String content;
  final PromptMessagePlacement placement;

  /// 复制消息，并允许覆盖常用字段。
  PromptMessage copyWith({
    String? id,
    PromptMessageRole? role,
    String? content,
    PromptMessagePlacement? placement,
  }) {
    return PromptMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      placement: placement ?? this.placement,
    );
  }

  /// 将消息序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.apiValue,
      'content': content,
      'placement': placement.apiValue,
    };
  }

  /// 从 JSON 反序列化消息。
  factory PromptMessage.fromJson(Map<String, dynamic> json) {
    return PromptMessage(
      id: json['id'] as String,
      role: PromptMessageRole.fromApiValue(json['role'] as String),
      content: json['content'] as String,
      placement: PromptMessagePlacement.fromApiValue(
        (json['placement'] as String?) ??
            PromptMessagePlacement.before.apiValue,
      ),
    );
  }

  @override
  List<Object> get props => [id, role, content, placement];
}

/// 可复用的 Prompt 模板，包含 system 指令和附加消息。
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

  /// 复制模板，并允许覆盖标题、指令、消息和更新时间。
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

  /// 将模板序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      'messages': messages.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化模板。
  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];

    return PromptTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      systemPrompt: json['systemPrompt'] as String,
      messages: rawMessages
          .map(
            (item) =>
                PromptMessage.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 返回模板内容的摘要，便于列表页快速浏览。
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
