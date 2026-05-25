import 'package:equatable/equatable.dart';

import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_conversation_summary.dart';
import 'chat_message_tree.dart';

/// 当前流式中的 assistant 消息增量。
///
/// 流式进行期间，控制器以此对象在内存中累积内容，
/// 只有到达刷新阈值时才将其写入 [activeChatConversationProvider]，
/// 从而控制 Markdown 渲染频率。
class ChatStreamingReply extends Equatable {
  const ChatStreamingReply({
    required this.conversationId,
    required this.assistantMessageId,
    this.content = '',
    this.reasoningContent = '',
  });

  /// 正在流式回复的会话 ID，用于校验当前 reply 是否属于活动会话。
  final String conversationId;

  /// 正在写入的 assistant 消息节点 ID。
  final String assistantMessageId;

  /// 已累积的回复正文（Markdown）。
  final String content;

  /// 已累积的推理过程文本（thinking 内容）。
  final String reasoningContent;

  ChatStreamingReply copyWith({
    String? conversationId,
    String? assistantMessageId,
    String? content,
    String? reasoningContent,
  }) {
    return ChatStreamingReply(
      conversationId: conversationId ?? this.conversationId,
      assistantMessageId: assistantMessageId ?? this.assistantMessageId,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
    );
  }

  @override
  List<Object?> get props => [
    conversationId,
    assistantMessageId,
    content,
    reasoningContent,
  ];
}

/// 当前聊天会话集合与活动会话状态。
///
/// 将流式增量 ([streamingReply]) 独立存储，而不是直接写进会话列表，
/// 目的是让流式刷新只触发 [activeChatConversationProvider] 重建，
/// 而不影响历史列表、导航栏等消费 [chatConversationsProvider] 的控件。
class ChatSessionsState extends Equatable {
  const ChatSessionsState({
    required this.conversations,
    required this.conversationSummaries,
    required this.activeConversationId,
    this.isStreaming = false,
    this.isCheckpointing = false,
    this.isAutoRetryWaiting = false,
    this.autoRetryCount = 0,
    this.errorMessage,
    this.errorMessageAssistantId,
    this.streamingReply,
    this.historyRevision = 0,
  });

  /// 所有持久化会话（按 [updatedAt] 倒序排列）。
  final List<ChatConversation> conversations;

  /// 全量会话的轻量摘要，供侧栏/历史页分组渲染。
  final List<ChatConversationSummary> conversationSummaries;

  /// 当前正在查看的会话 ID。
  final String activeConversationId;

  /// 是否有流式请求正在进行。
  final bool isStreaming;

  /// 是否正在创建检查点。
  final bool isCheckpointing;

  /// 是否正在等待自动重试的发送窗口。
  final bool isAutoRetryWaiting;

  /// 当前自动重试的尝试次数，成功回复后清零。
  final int autoRetryCount;

  /// 最近一次错误的用户可读描述，正常时为 `null`。
  final String? errorMessage;

  /// 需要展示错误提示的 assistant 消息 ID。
  final String? errorMessageAssistantId;

  /// 正在进行中的流式增量，流结束后清空。
  final ChatStreamingReply? streamingReply;

  /// 历史列表变更版本号，每次写入会话时递增，供历史页触发重新查询。
  final int historyRevision;

  /// 获取当前正在展示的会话；找不到时回退到列表首项。
  ChatConversation get activeConversation {
    return conversations.firstWhere(
      (conversation) => conversation.id == activeConversationId,
      orElse: () => conversations.first,
    );
  }

  /// 复制状态并按需替换会话列表、活动会话和错误信息。
  ChatSessionsState copyWith({
    List<ChatConversation>? conversations,
    List<ChatConversationSummary>? conversationSummaries,
    String? activeConversationId,
    bool? isStreaming,
    bool? isCheckpointing,
    bool? isAutoRetryWaiting,
    int? autoRetryCount,
    bool clearAutoRetryCount = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? errorMessageAssistantId,
    ChatStreamingReply? streamingReply,
    bool clearStreamingReply = false,
    int? historyRevision,
    bool incrementHistoryRevision = false,
  }) {
    return ChatSessionsState(
      conversations: conversations ?? this.conversations,
      conversationSummaries:
          conversationSummaries ?? this.conversationSummaries,
      activeConversationId: activeConversationId ?? this.activeConversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      isCheckpointing: isCheckpointing ?? this.isCheckpointing,
      isAutoRetryWaiting: isAutoRetryWaiting ?? this.isAutoRetryWaiting,
      autoRetryCount: clearAutoRetryCount
          ? 0
          : autoRetryCount ?? this.autoRetryCount,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      errorMessageAssistantId: clearErrorMessage
          ? null
          : errorMessageAssistantId ?? this.errorMessageAssistantId,
      streamingReply: clearStreamingReply
          ? null
          : streamingReply ?? this.streamingReply,
      historyRevision: incrementHistoryRevision
          ? this.historyRevision + 1
          : historyRevision ?? this.historyRevision,
    );
  }

  @override
  List<Object?> get props => [
    conversations,
    conversationSummaries,
    activeConversationId,
    isStreaming,
    isCheckpointing,
    isAutoRetryWaiting,
    autoRetryCount,
    errorMessage,
    errorMessageAssistantId,
    streamingReply,
    historyRevision,
  ];
}

/// 将流式增量合并进 [conversation]，返回一个带最新内容的临时会话快照。
///
/// 此函数是纯函数，不修改任何状态，专供 [activeChatConversationProvider] 和
/// 流式结束后的最终落盘使用。当 [streamingReply] 为 `null` 或 ID 不匹配时，
/// 原样返回 [conversation]，不做任何变更。
ChatConversation applyStreamingReplyToConversation({
  required ChatConversation conversation,
  required ChatStreamingReply? streamingReply,
  bool isStreaming = true,
}) {
  if (streamingReply == null ||
      streamingReply.conversationId != conversation.id) {
    return conversation;
  }

  final nextTree = replaceAssistantMessageInTree(
    treeState: resolveMessageTreeState(conversation),
    assistantMessageId: streamingReply.assistantMessageId,
    nextContent: streamingReply.content,
    nextReasoningContent: streamingReply.reasoningContent,
    isStreaming: isStreaming,
  );
  return conversation.copyWith(
    messageNodes: nextTree.nodes,
    selectedChildByParentId: nextTree.selections,
  );
}
