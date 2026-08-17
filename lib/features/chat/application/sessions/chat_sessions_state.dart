import 'package:equatable/equatable.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_conversation_summary.dart';
import '../generation/chat_generation_lifecycle.dart';
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
    this.finishReason,
  });

  /// 正在流式回复的会话 ID，用于校验当前 reply 是否属于活动会话。
  final String conversationId;

  /// 正在写入的 assistant 消息节点 ID。
  final String assistantMessageId;

  /// 已累积的回复正文（Markdown）。
  final String content;

  /// 已累积的推理过程文本（thinking 内容）。
  final String reasoningContent;

  /// 流式结束原因（如 "stop"、"length"），流式进行中为 `null`。
  final String? finishReason;

  ChatStreamingReply copyWith({
    String? conversationId,
    String? assistantMessageId,
    String? content,
    String? reasoningContent,
    String? finishReason,
  }) {
    return ChatStreamingReply(
      conversationId: conversationId ?? this.conversationId,
      assistantMessageId: assistantMessageId ?? this.assistantMessageId,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      finishReason: finishReason ?? this.finishReason,
    );
  }

  @override
  List<Object?> get props => [
    conversationId,
    assistantMessageId,
    content,
    reasoningContent,
    finishReason,
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
    this.isCheckpointing = false,
    this.errorMessage,
    this.errorMessageAssistantId,
    this.emptyReplyAssistantId,
    this.streamingReply,
    this.historyRevision = 0,
    this.pendingScrollToMessageId,
    this.generation,
  });

  /// 所有持久化会话（按 [updatedAt] 倒序排列）。
  final List<ChatConversation> conversations;

  /// 全量会话的轻量摘要，供侧栏/历史页分组渲染。
  final List<ChatConversationSummary> conversationSummaries;

  /// 当前正在查看的会话 ID。
  final String activeConversationId;

  /// 是否处于流式/准备阶段（由 [generation] 派生，无独立存储）。
  ///
  /// 派生自 [ChatGenerationSnapshot.phase]：`preparing`/`streaming` 为 true。
  /// `preparing` 也计入 true，使 ComposerSendButton 的 isStopping 在 prepare
  /// 期间保持停止按钮可用。controller 不单独维护此值。
  bool get isStreaming {
    final phase = generation?.phase;
    return phase == ChatGenerationPhase.preparing ||
        phase == ChatGenerationPhase.streaming;
  }

  /// 是否正在创建检查点。
  final bool isCheckpointing;

  /// 是否正在等待自动重试的发送窗口（由 [generation] 派生，无独立存储）。
  bool get isAutoRetryWaiting =>
      generation?.phase == ChatGenerationPhase.retryWaiting;

  /// 当前自动重试的尝试次数，成功回复后清零（由 [generation] 派生，无独立存储）。
  ///
  /// 仅在 `retryWaiting`/`streaming` 阶段投影 `attempt-1`（显示「第 N 次重试
  /// 中」）；终态、`preparing`/`finalizing`/`stopping` 或空闲时投影 0，避免
  /// attempt 终态保存窗口误显示重试中。
  int get autoRetryCount {
    final snapshot = generation;
    if (snapshot == null || snapshot.outcome != null) return 0;
    final phase = snapshot.phase;
    final showsRetry =
        phase == ChatGenerationPhase.retryWaiting ||
        phase == ChatGenerationPhase.streaming;
    return showsRetry && snapshot.attempt > 0 ? snapshot.attempt - 1 : 0;
  }

  /// 最近一次错误的用户可读描述，正常时为 `null`。
  final String? errorMessage;

  /// 需要展示错误提示的 assistant 消息 ID。
  final String? errorMessageAssistantId;

  /// 需要展示空回复提示的 assistant 消息 ID。
  final String? emptyReplyAssistantId;

  /// 正在进行中的流式增量，流结束后清空。
  final ChatStreamingReply? streamingReply;

  /// 当前 generation 的生命周期快照；无进行中 generation 时为 null。
  ///
  /// 这是生命周期状态的唯一事实来源：`isStreaming` / `isAutoRetryWaiting` /
  /// [autoRetryCount] 均由本快照的 `phase`/`attempt` 单向派生。消费方按需读取
  /// `snapshot.phase` 以获得比布尔更细粒度的生命周期信息，例如区分
  /// `streaming` 与 attempt 终态后等待 durable save 的 `finalizing`。
  final ChatGenerationSnapshot? generation;

  /// 历史列表变更版本号，每次写入会话时递增，供历史页触发重新查询。
  final int historyRevision;

  /// 导航后需要滚动到的消息 ID，消费后应清空。
  final String? pendingScrollToMessageId;

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
    bool? isCheckpointing,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? errorMessageAssistantId,
    String? emptyReplyAssistantId,
    bool clearEmptyReply = false,
    ChatStreamingReply? streamingReply,
    bool clearStreamingReply = false,
    ChatGenerationSnapshot? generation,
    bool clearGeneration = false,
    int? historyRevision,
    bool incrementHistoryRevision = false,
    String? pendingScrollToMessageId,
    bool clearPendingScrollToMessageId = false,
  }) {
    return ChatSessionsState(
      conversations: conversations ?? this.conversations,
      conversationSummaries:
          conversationSummaries ?? this.conversationSummaries,
      activeConversationId: activeConversationId ?? this.activeConversationId,
      isCheckpointing: isCheckpointing ?? this.isCheckpointing,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      errorMessageAssistantId: clearErrorMessage
          ? null
          : errorMessageAssistantId ?? this.errorMessageAssistantId,
      emptyReplyAssistantId: clearEmptyReply
          ? null
          : emptyReplyAssistantId ?? this.emptyReplyAssistantId,
      streamingReply: clearStreamingReply
          ? null
          : streamingReply ?? this.streamingReply,
      generation: clearGeneration ? null : generation ?? this.generation,
      historyRevision: incrementHistoryRevision
          ? this.historyRevision + 1
          : historyRevision ?? this.historyRevision,
      pendingScrollToMessageId: clearPendingScrollToMessageId
          ? null
          : pendingScrollToMessageId ?? this.pendingScrollToMessageId,
    );
  }

  @override
  List<Object?> get props => [
    conversations,
    conversationSummaries,
    activeConversationId,
    isCheckpointing,
    errorMessage,
    errorMessageAssistantId,
    emptyReplyAssistantId,
    streamingReply,
    generation,
    historyRevision,
    pendingScrollToMessageId,
  ];
}

/// 校验 generation snapshot 不变量（debug 模式触发，release 无开销）。
///
/// terminal phase 必有 outcome，non-terminal 不得有 outcome；outcome 的
/// generationId/attempt 与 snapshot 一致。违反即 throw StateError，暴露
/// 状态机的不变量裂缝。由 controller 在把 snapshot 写入 state 前调用。
bool checkGenerationInvariants(ChatGenerationSnapshot snapshot) {
  final phase = snapshot.phase;
  final outcome = snapshot.outcome;
  if (phase.isTerminal && outcome == null) {
    throw StateError('terminal phase $phase 必须有 outcome');
  }
  if (!phase.isTerminal && outcome != null) {
    throw StateError('non-terminal phase $phase 不得有 outcome');
  }
  if (outcome != null) {
    if (outcome.generationId != snapshot.generationId) {
      throw StateError(
        'generationId 不一致：snapshot=${snapshot.generationId}, '
        'outcome=${outcome.generationId}',
      );
    }
    if (outcome.attempt != snapshot.attempt) {
      throw StateError(
        'attempt 不一致：snapshot=${snapshot.attempt}, '
        'outcome=${outcome.attempt}',
      );
    }
  }
  return true;
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
    finishReason: streamingReply.finishReason,
  );
  return conversation.copyWith(
    messageNodes: nextTree.nodes,
    selectedChildByParentId: nextTree.selections,
  );
}
