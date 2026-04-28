import 'package:equatable/equatable.dart';

/// 一条收藏记录，保存收藏时刻的用户消息与模型回复内容的完整副本。
///
/// 内容独立于原始对话，删除对话不会影响收藏内容。
/// [sourceConversationId] 仅作参考，不建立外键约束。
class Favorite extends Equatable {
  const Favorite({
    required this.id,
    required this.userMessageContent,
    required this.assistantContent,
    required this.createdAt,
    this.collectionId,
    this.assistantReasoningContent = '',
    this.sourceConversationId,
    this.sourceConversationTitle,
  });

  final String id;

  /// 所属收藏夹 ID；为 null 表示未分类。
  final String? collectionId;

  /// 收藏时用户消息的文本内容。
  final String userMessageContent;

  /// 收藏时模型回复的文本内容。
  final String assistantContent;

  /// 收藏时模型深度思考的推理内容；无推理时为空字符串。
  final String assistantReasoningContent;

  /// 来源对话 ID；对话可能已被删除。
  final String? sourceConversationId;

  /// 收藏时来源对话的标题副本。
  final String? sourceConversationTitle;

  /// 收藏时间。
  final DateTime createdAt;

  /// 是否含有推理内容。
  bool get hasReasoning => assistantReasoningContent.isNotEmpty;

  /// 复制收藏，并允许覆盖单个字段。
  Favorite copyWith({
    String? id,
    String? collectionId,
    String? userMessageContent,
    String? assistantContent,
    String? assistantReasoningContent,
    String? sourceConversationId,
    String? sourceConversationTitle,
    DateTime? createdAt,
    bool clearCollectionId = false,
  }) {
    return Favorite(
      id: id ?? this.id,
      collectionId:
          clearCollectionId ? null : collectionId ?? this.collectionId,
      userMessageContent: userMessageContent ?? this.userMessageContent,
      assistantContent: assistantContent ?? this.assistantContent,
      assistantReasoningContent:
          assistantReasoningContent ?? this.assistantReasoningContent,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      sourceConversationTitle:
          sourceConversationTitle ?? this.sourceConversationTitle,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    collectionId,
    userMessageContent,
    assistantContent,
    assistantReasoningContent,
    sourceConversationId,
    sourceConversationTitle,
    createdAt,
  ];
}
