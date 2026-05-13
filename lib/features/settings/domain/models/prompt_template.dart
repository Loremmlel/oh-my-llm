import 'dart:convert';

import 'package:equatable/equatable.dart';

const defaultSystemPromptTitle = 'system';

/// Prompt 模板中附加消息的发送角色。
enum PromptMessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const PromptMessageRole(this.apiValue);

  final String apiValue;

  /// 返回更适合界面展示的角色标签。
  String get label => switch (this) {
    PromptMessageRole.system => 'System',
    PromptMessageRole.user => 'User',
    PromptMessageRole.assistant => 'Assistant',
  };

  /// 从 API 字符串值解析角色枚举。
  static PromptMessageRole fromApiValue(String value) {
    return PromptMessageRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => PromptMessageRole.user,
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

/// 可复用的 Prompt 模板，使用统一消息列表表示 system / user / assistant 条目。
class PromptTemplate extends Equatable {
  PromptTemplate({
    required this.id,
    required this.name,
    required List<PromptMessage> messages,
    required this.updatedAt,
    String systemPrompt = '',
    String systemPromptTitle = defaultSystemPromptTitle,
  }) : messages = _normalizePromptTemplateMessages(
         messages,
         legacySystemPrompt: systemPrompt,
         legacySystemPromptTitle: systemPromptTitle,
       );

  final String id;
  final String name;
  final List<PromptMessage> messages;
  final DateTime updatedAt;

  /// 为旧代码提供兼容读取：返回第一条 system 消息内容。
  String get systemPrompt => _firstSystemMessage?.content ?? '';

  /// 为旧代码提供兼容读取：返回第一条 system 消息标题。
  String get systemPromptTitle =>
      _firstSystemMessage?.title ?? defaultSystemPromptTitle;

  PromptMessage? get _firstSystemMessage {
    for (final message in messages) {
      if (message.role == PromptMessageRole.system) {
        return message;
      }
    }
    return null;
  }

  Iterable<PromptMessage> messagesForPlacement(
    PromptMessagePlacement placement,
  ) {
    return messages.where((message) => message.placement == placement);
  }

  /// 复制模板，并允许覆盖标题、消息和更新时间。
  ///
  /// `systemPrompt` / `systemPromptTitle` 仅保留给旧调用方，语义为“替换第一条
  /// system 消息”；新的实现应直接传入完整的 `messages`。
  PromptTemplate copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    List<PromptMessage>? messages,
    DateTime? updatedAt,
    String? systemPromptTitle,
  }) {
    final nextMessages = messages ?? this.messages;
    final shouldReplaceLegacySystem =
        systemPrompt != null || systemPromptTitle != null;
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      messages: shouldReplaceLegacySystem
          ? _replaceLegacySystemMessage(
              nextMessages,
              systemPrompt: systemPrompt ?? this.systemPrompt,
              systemPromptTitle: systemPromptTitle ?? this.systemPromptTitle,
            )
          : nextMessages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 将模板序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'systemPrompt': systemPrompt,
      'systemPromptTitle': systemPromptTitle,
      'messages': messages.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 反序列化模板。
  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    final messages = _deserializePromptMessages(rawMessages);
    final hasSystemMessages = messages.any(
      (message) => message.role == PromptMessageRole.system,
    );

    return PromptTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      systemPrompt: hasSystemMessages
          ? ''
          : (json['systemPrompt'] as String? ?? ''),
      systemPromptTitle:
          (json['systemPromptTitle'] as String?)?.trim().isNotEmpty == true
          ? json['systemPromptTitle'] as String
          : defaultSystemPromptTitle,
      messages: messages,
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

List<PromptMessage> _normalizePromptTemplateMessages(
  List<PromptMessage> messages, {
  required String legacySystemPrompt,
  required String legacySystemPromptTitle,
}) {
  final normalizedMessages = List<PromptMessage>.unmodifiable(messages);
  if (normalizedMessages.any(
    (message) => message.role == PromptMessageRole.system,
  )) {
    return normalizedMessages;
  }

  final trimmedLegacySystemPrompt = legacySystemPrompt.trim();
  if (trimmedLegacySystemPrompt.isEmpty) {
    return normalizedMessages;
  }

  final title = legacySystemPromptTitle.trim().isEmpty
      ? defaultSystemPromptTitle
      : legacySystemPromptTitle.trim();
  return List<PromptMessage>.unmodifiable([
    PromptMessage(
      id: '_legacy-system-message',
      role: PromptMessageRole.system,
      title: title,
      content: trimmedLegacySystemPrompt,
      placement: PromptMessagePlacement.before,
    ),
    ...normalizedMessages,
  ]);
}

List<PromptMessage> _replaceLegacySystemMessage(
  List<PromptMessage> messages, {
  required String systemPrompt,
  required String systemPromptTitle,
}) {
  final mutableMessages = List<PromptMessage>.from(messages);
  final systemIndex = mutableMessages.indexWhere(
    (message) => message.role == PromptMessageRole.system,
  );
  final existingSystemId = systemIndex == -1
      ? '_legacy-system-message'
      : mutableMessages.removeAt(systemIndex).id;
  final trimmedSystemPrompt = systemPrompt.trim();
  if (trimmedSystemPrompt.isEmpty) {
    return List<PromptMessage>.unmodifiable(mutableMessages);
  }

  final title = systemPromptTitle.trim().isEmpty
      ? defaultSystemPromptTitle
      : systemPromptTitle.trim();
  mutableMessages.insert(
    0,
    PromptMessage(
      id: existingSystemId,
      role: PromptMessageRole.system,
      title: title,
      content: trimmedSystemPrompt,
      placement: PromptMessagePlacement.before,
    ),
  );
  return List<PromptMessage>.unmodifiable(mutableMessages);
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
