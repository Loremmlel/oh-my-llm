import 'package:equatable/equatable.dart';

import '../../../../core/constants/model_display_name.dart';

/// 聊天消息的发送角色。
enum ChatMessageRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const ChatMessageRole(this.apiValue);

  final String apiValue;
}

/// 模型推理强度枚举，保持与 API 的字符串值一致。
enum ReasoningEffort {
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh');

  const ReasoningEffort(this.apiValue);

  final String apiValue;
}

/// 用户消息中的一个可着色文本片段。
enum UserMessageSegmentKind {
  body('body'),
  template('template');

  const UserMessageSegmentKind(this.apiValue);

  final String apiValue;

  /// 从持久化字符串解析片段类型。
  static UserMessageSegmentKind fromApiValue(String value) {
    return UserMessageSegmentKind.values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () => UserMessageSegmentKind.body,
    );
  }
}

/// 用户消息展示时的一个文本片段。
class UserMessageSegment extends Equatable {
  const UserMessageSegment({
    required this.text,
    required this.kind,
  });

  final String text;
  final UserMessageSegmentKind kind;

  /// 将片段序列化为持久化 JSON。
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'kind': kind.apiValue,
    };
  }

  /// 从持久化 JSON 反序列化片段。
  factory UserMessageSegment.fromJson(Map<String, dynamic> json) {
    return UserMessageSegment(
      text: json['text'] as String,
      kind: UserMessageSegmentKind.fromApiValue(json['kind'] as String),
    );
  }

  @override
  List<Object> get props => [text, kind];
}

/// 单条聊天消息，包含正文、推理内容和树结构位置。
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.isStreaming = false,
    this.reasoningContent = '',
    this.assistantModelDisplayName = '',
    this.appliedCheckpointTitle = '',
    this.userMessageSegments = const [],
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final DateTime createdAt;
  final String? parentId;
  final bool isStreaming;
  final String reasoningContent;
  final String assistantModelDisplayName;
  final String appliedCheckpointTitle;
  final List<UserMessageSegment> userMessageSegments;

  /// 复制消息，并允许覆盖常用字段。
  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? content,
    DateTime? createdAt,
    String? parentId,
    bool? isStreaming,
    String? reasoningContent,
    String? assistantModelDisplayName,
    String? appliedCheckpointTitle,
    List<UserMessageSegment>? userMessageSegments,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      isStreaming: isStreaming ?? this.isStreaming,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      assistantModelDisplayName:
          assistantModelDisplayName ?? this.assistantModelDisplayName,
      appliedCheckpointTitle:
          appliedCheckpointTitle ?? this.appliedCheckpointTitle,
      userMessageSegments: userMessageSegments ?? this.userMessageSegments,
    );
  }

  /// 将消息序列化为持久化 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.apiValue,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'parentId': parentId,
      'reasoningContent': reasoningContent,
      'assistantModelDisplayName': assistantModelDisplayName,
      'appliedCheckpointTitle': appliedCheckpointTitle,
      'userMessageSegments':
          userMessageSegments.map((segment) => segment.toJson()).toList(),
    };
  }

  /// 从持久化 JSON 反序列化消息。
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = ChatMessageRole.values.firstWhere(
      (role) => role.apiValue == json['role'],
    );
    final rawSegments = json['userMessageSegments'] as List<dynamic>? ?? const [];
    return ChatMessage(
      id: json['id'] as String,
      role: role,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      parentId: json['parentId'] as String?,
      reasoningContent: json['reasoningContent'] as String? ?? '',
      assistantModelDisplayName:
          json['assistantModelDisplayName'] as String? ??
          (role == ChatMessageRole.assistant
              ? anonymousAssistantModelDisplayName
              : ''),
      appliedCheckpointTitle: json['appliedCheckpointTitle'] as String? ?? '',
      userMessageSegments: rawSegments
          .map(
            (segment) => UserMessageSegment.fromJson(
              Map<String, dynamic>.from(segment as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  /// 用于 UI 展示的助手模型名称；为空时回退匿名名称。
  String get resolvedAssistantModelDisplayName {
    final normalized = assistantModelDisplayName.trim();
    return normalized.isEmpty ? anonymousAssistantModelDisplayName : normalized;
  }

  @override
  List<Object?> get props => [
    id,
    role,
    content,
    createdAt,
    parentId,
    isStreaming,
    reasoningContent,
    assistantModelDisplayName,
    appliedCheckpointTitle,
    userMessageSegments,
  ];
}
