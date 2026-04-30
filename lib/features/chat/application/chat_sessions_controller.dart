import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/chat_defaults_controller.dart';
import '../../settings/application/llm_model_configs_controller.dart';
import '../../settings/application/prompt_templates_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
import 'chat_message_tree.dart';
import 'chat_request_message_builder.dart';
import '../data/chat_completion_client.dart';
import '../data/chat_conversation_repository.dart';
import '../data/openai_compatible_chat_client.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

/// 主入口 provider，暴露完整会话状态和操作接口。
final chatSessionsProvider =
    NotifierProvider<ChatSessionsController, ChatSessionsState>(
      ChatSessionsController.new,
    );

/// UI 刷新节流阈值：流式增量积累满此间隔才触发一次界面重建，
/// 避免高频 token 回调把单帧渲染时间占满。
const _streamUiFlushInterval = Duration(milliseconds: 300);

/// 当前所有聊天会话列表（仅在会话增删改时重建）。
final chatConversationsProvider = Provider<List<ChatConversation>>((ref) {
  return ref.watch(chatSessionsProvider.select((state) => state.conversations));
});

/// 当前活动会话的 ID（仅在切换会话时重建）。
final activeConversationIdProvider = Provider<String>((ref) {
  return ref.watch(
    chatSessionsProvider.select((state) => state.activeConversationId),
  );
});

/// 是否正在进行流式请求（仅在流开始/结束时重建）。
final isChatStreamingProvider = Provider<bool>((ref) {
  return ref.watch(chatSessionsProvider.select((state) => state.isStreaming));
});

/// 当前错误提示文字，无错误时为 `null`（仅在错误状态变化时重建）。
final chatErrorMessageProvider = Provider<String?>((ref) {
  return ref.watch(chatSessionsProvider.select((state) => state.errorMessage));
});

/// 历史列表变更计数器，每次会话增删改时递增，供历史页触发重新查询。
final chatHistoryRevisionProvider = Provider<int>((ref) {
  return ref.watch(
    chatSessionsProvider.select((state) => state.historyRevision),
  );
});

/// 当前活动会话的完整视图，已将流式增量合并进消息列表（高频刷新）。
///
/// 流式进行期间，此 provider 每次 [_streamUiFlushInterval] 重建一次，
/// 而 [chatConversationsProvider] 和 [chatHistoryRevisionProvider] 保持静止，
/// 以此隔离高频重建的影响范围。
final activeChatConversationProvider = Provider<ChatConversation>((ref) {
  final state = ref.watch(chatSessionsProvider);
  return _applyStreamingReplyToConversation(
    conversation: state.activeConversation,
    streamingReply: state.streamingReply,
  );
});

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
    required this.activeConversationId,
    this.isStreaming = false,
    this.errorMessage,
    this.streamingReply,
    this.historyRevision = 0,
  });

  /// 所有持久化会话（按 [updatedAt] 倒序排列）。
  final List<ChatConversation> conversations;

  /// 当前正在查看的会话 ID。
  final String activeConversationId;

  /// 是否有流式请求正在进行。
  final bool isStreaming;

  /// 最近一次错误的用户可读描述，正常时为 `null`。
  final String? errorMessage;

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
    String? activeConversationId,
    bool? isStreaming,
    String? errorMessage,
    bool clearErrorMessage = false,
    ChatStreamingReply? streamingReply,
    bool clearStreamingReply = false,
    int? historyRevision,
    bool incrementHistoryRevision = false,
  }) {
    return ChatSessionsState(
      conversations: conversations ?? this.conversations,
      activeConversationId: activeConversationId ?? this.activeConversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
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
    activeConversationId,
    isStreaming,
    errorMessage,
    streamingReply,
    historyRevision,
  ];
}

/// 将流式增量合并进 [conversation]，返回一个带最新内容的临时会话快照。
///
/// 此函数是纯函数，不修改任何状态，专供 [activeChatConversationProvider] 和
/// 流式结束后的最终落盘使用。当 [streamingReply] 为 `null` 或 ID 不匹配时，
/// 原样返回 [conversation]，不做任何变更。
ChatConversation _applyStreamingReplyToConversation({
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

/// 聊天页面的会话编排器，负责发送、重试、编辑和持久化。
class ChatSessionsController extends Notifier<ChatSessionsState> {
  ChatConversationRepository get _repository =>
      ref.read(chatConversationRepositoryProvider);

  ChatCompletionClient get _chatClient =>
      ref.read(chatCompletionClientProvider);

  // ── 生命周期 ────────────────────────────────────────────────────────────────

  /// 读取持久化数据并初始化当前会话状态。
  ///
  /// 若数据库为空则自动创建一个新的空白会话作为初始状态。
  @override
  ChatSessionsState build() {
    final conversations = _sort(_repository.loadAll());
    final initialConversation = conversations.isEmpty
        ? _createConversation()
        : conversations.first;

    return ChatSessionsState(
      conversations: conversations.isEmpty
          ? [initialConversation]
          : List.unmodifiable(conversations),
      activeConversationId: initialConversation.id,
    );
  }

  // ── 公开操作 ────────────────────────────────────────────────────────────────

  /// 新建一个会话并切换到该会话。
  Future<void> createConversation() async {
    final currentConversation = state.activeConversation;
    if (!currentConversation.hasMessages) {
      return;
    }

    final nextConversation = _createConversation();
    state = state.copyWith(
      conversations: [nextConversation, ...state.conversations],
      activeConversationId: nextConversation.id,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await _saveAll();
  }

  /// 选择一个已存在的会话作为活动会话。
  void selectConversation(String id) {
    final hasMatch = state.conversations.any((conversation) {
      return conversation.id == id;
    });
    if (!hasMatch || state.activeConversationId == id) {
      return;
    }

    state = state.copyWith(activeConversationId: id, clearErrorMessage: true);
  }

  /// 重命名当前活动会话。
  Future<void> renameActiveConversation(String title) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }

    await _updateActiveConversation(
      state.activeConversation.copyWith(
        title: nextTitle,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 重命名单个会话。
  Future<void> renameConversation({
    required String conversationId,
    required String title,
  }) async {
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }

    final targetConversation = state.conversations.where((conversation) {
      return conversation.id == conversationId;
    }).firstOrNull;
    if (targetConversation == null) {
      return;
    }

    state = state.copyWith(
      conversations: _replaceConversation(
        targetConversation.copyWith(
          title: nextTitle,
          updatedAt: DateTime.now(),
        ),
      ),
      incrementHistoryRevision: true,
    );
    await _saveAll();
  }

  /// 删除一组会话，必要时回退到新的空会话。
  Future<void> deleteConversations(Set<String> conversationIds) async {
    if (conversationIds.isEmpty || state.isStreaming) {
      return;
    }

    final remainingConversations = state.conversations
        .where((conversation) {
          return !conversationIds.contains(conversation.id);
        })
        .toList(growable: false);

    final fallbackConversation =
        remainingConversations.firstOrNull ?? _createConversation();

    state = state.copyWith(
      conversations: remainingConversations.isEmpty
          ? [fallbackConversation]
          : remainingConversations,
      activeConversationId:
          remainingConversations.any((conversation) {
            return conversation.id == state.activeConversationId;
          })
          ? state.activeConversationId
          : fallbackConversation.id,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await _saveAll();
  }

  /// 更新当前会话的默认模型和 Prompt 相关偏好。
  Future<void> updateActiveConversationPreferences({
    String? selectedModelId,
    String? selectedPromptTemplateId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool clearSelectedPromptTemplateId = false,
  }) {
    return _updateActiveConversation(
      state.activeConversation.copyWith(
        selectedModelId: selectedModelId,
        selectedPromptTemplateId: selectedPromptTemplateId,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: reasoningEffort,
        clearSelectedPromptTemplateId: clearSelectedPromptTemplateId,
      ),
    );
  }

  /// 切换某个父节点下的选中消息版本。
  Future<void> selectMessageVersion({
    required String parentId,
    required String messageId,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final currentConversation = state.activeConversation;
    final tree = resolveMessageTreeState(currentConversation);
    final siblings = tree.nodes
        .where((node) {
          return (node.parentId ?? rootConversationParentId) == parentId;
        })
        .toList(growable: false);
    final hasTarget = siblings.any((node) => node.id == messageId);
    if (!hasTarget) {
      return;
    }

    final nextSelections = Map<String, String>.from(tree.selections);
    nextSelections[parentId] = messageId;
    await _updateActiveConversation(
      currentConversation.copyWith(
        messageNodes: tree.nodes,
        selectedChildByParentId: nextSelections,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 编辑一条用户消息并从该节点重新生成后续回复。
  Future<void> editMessage({
    required String messageId,
    required String nextContent,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final trimmedContent = nextContent.trim();
    if (trimmedContent.isEmpty) {
      return;
    }

    final currentConversation = state.activeConversation;
    final tree = resolveMessageTreeState(currentConversation);
    final targetMessage = tree.nodes.where((message) {
      return message.id == messageId && message.role == ChatMessageRole.user;
    }).firstOrNull;
    if (targetMessage == null) {
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重算：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    final branchUserMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: DateTime.now(),
      parentId: targetMessage.parentId,
    );
    final nextNodes = [...tree.nodes, branchUserMessage];
    final nextSelections = Map<String, String>.from(tree.selections);
    final branchParentId = targetMessage.parentId ?? rootConversationParentId;
    nextSelections[branchParentId] = branchUserMessage.id;
    final rebuiltConversation = currentConversation.copyWith(
      messageNodes: nextNodes,
      selectedChildByParentId: nextSelections,
      updatedAt: DateTime.now(),
    );
    await _streamAssistantReply(
      conversation: rebuiltConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: rebuiltConversation.messages,
      parentMessageId: branchUserMessage.id,
      reasoningEnabled: rebuiltConversation.reasoningEnabled,
      reasoningEffort: rebuiltConversation.reasoningEffort,
    );
  }

  /// 重新请求当前对话中最新的一条模型回复。
  Future<void> retryLatestAssistant() async {
    if (state.isStreaming) {
      return;
    }

    final currentConversation = state.activeConversation;
    final activePath = currentConversation.messages;
    final latestMessage = activePath.lastOrNull;
    if (latestMessage == null) {
      _setErrorMessage('只能重试当前对话中的最新模型回复。');
      return;
    }

    final modelConfig = _resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      _setErrorMessage('无法重试：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = _resolvePromptTemplate(currentConversation);
    if (latestMessage.role == ChatMessageRole.user &&
        state.errorMessage != null) {
      await _streamAssistantReply(
        conversation: currentConversation.copyWith(updatedAt: DateTime.now()),
        modelConfig: modelConfig,
        promptTemplate: promptTemplate,
        requestConversationMessages: activePath,
        parentMessageId: latestMessage.id,
        reasoningEnabled: currentConversation.reasoningEnabled,
        reasoningEffort: currentConversation.reasoningEffort,
      );
      return;
    }

    final latestAssistantIndex = activePath.lastIndexWhere((message) {
      return message.role == ChatMessageRole.assistant;
    });
    if (latestAssistantIndex == -1 ||
        latestAssistantIndex != activePath.length - 1) {
      _setErrorMessage('只能重试当前对话中的最新模型回复。');
      return;
    }

    final tree = resolveMessageTreeState(currentConversation);
    final latestAssistant = activePath[latestAssistantIndex];
    final parentId = latestAssistant.parentId ?? rootConversationParentId;
    final requestMessages = activePath
        .take(latestAssistantIndex)
        .toList(growable: false);
    final nextSelections = Map<String, String>.from(tree.selections);
    nextSelections.remove(parentId);
    final baseConversation = currentConversation.copyWith(
      messageNodes: tree.nodes,
      selectedChildByParentId: nextSelections,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      conversations: _replaceConversation(baseConversation),
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await _saveAll();

    await _streamAssistantReply(
      conversation: baseConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: requestMessages,
      parentMessageId: parentId == rootConversationParentId ? null : parentId,
      reasoningEnabled: baseConversation.reasoningEnabled,
      reasoningEffort: baseConversation.reasoningEffort,
    );
  }


  /// 发送新消息并触发模型流式回复。
  Future<void> sendMessage({
    required String content,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
  }) async {
    if (state.isStreaming) {
      return;
    }

    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      return;
    }

    final currentConversation = state.activeConversation;
    final timestamp = DateTime.now();
    final tree = resolveMessageTreeState(currentConversation);
    final activePath = currentConversation.messages;
    final parentId = activePath.lastOrNull?.id;
    final userMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: timestamp,
      parentId: parentId ?? rootConversationParentId,
    );
    final pendingNodes = [...tree.nodes, userMessage];
    final pendingSelections = Map<String, String>.from(tree.selections);
    pendingSelections[parentId ?? rootConversationParentId] = userMessage.id;

    final pendingConversation = currentConversation.copyWith(
      messageNodes: pendingNodes,
      selectedChildByParentId: pendingSelections,
      updatedAt: timestamp,
      selectedPromptTemplateId: promptTemplate?.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
    await _streamAssistantReply(
      conversation: pendingConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: pendingConversation.messages,
      parentMessageId: userMessage.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
  }

  // ── 私有辅助 ────────────────────────────────────────────────────────────────

  /// 创建一个空会话并继承设置页中的默认选择。
  ChatConversation _createConversation() {
    final now = DateTime.now();
    final chatDefaults = ref.read(chatDefaultsProvider);
    return ChatConversation(
      id: generateEntityId(),
      messages: const [],
      createdAt: now,
      updatedAt: now,
      selectedPromptTemplateId: chatDefaults.defaultPromptTemplateId,
      reasoningEffort: ReasoningEffort.medium,
    );
  }

  /// 在流式请求失败时，保留已生成内容或清除空白占位节点。
  Future<void> _handleStreamingFailure({
    required ChatConversation conversation,
    required ChatStreamingReply streamingReply,
    required String assistantMessageId,
    required String errorMessage,
  }) async {
    final hasPartialContent =
        streamingReply.content.trim().isNotEmpty ||
        streamingReply.reasoningContent.trim().isNotEmpty;
    final tree = resolveMessageTreeState(conversation);

    final nextTree = hasPartialContent
        ? replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: assistantMessageId,
            nextContent: streamingReply.content,
            nextReasoningContent: streamingReply.reasoningContent,
            isStreaming: false,
          )
        : removeNodeFromTree(treeState: tree, nodeId: assistantMessageId);

    final nextConversation = conversation.copyWith(
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      conversations: _replaceConversation(nextConversation),
      isStreaming: false,
      errorMessage: errorMessage,
      clearStreamingReply: true,
      incrementHistoryRevision: true,
    );
    await _saveAll();
  }

  /// 替换当前活动会话并同步持久化。
  Future<void> _updateActiveConversation(ChatConversation conversation) async {
    state = state.copyWith(
      conversations: _replaceConversation(conversation),
      incrementHistoryRevision: true,
    );
    await _saveAll();
  }

  /// 把 assistant 回复以流式方式写回当前会话。
  Future<ChatConversation?> _streamAssistantReply({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required List<ChatMessage> requestConversationMessages,
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
  }) async {
    final timestamp = DateTime.now();
    final tree = resolveMessageTreeState(conversation);
    final assistantParentId = parentMessageId ?? rootConversationParentId;
    final assistantMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: timestamp.add(const Duration(milliseconds: 1)),
      parentId: assistantParentId,
      isStreaming: true,
      assistantModelDisplayName: modelConfig.displayName,
    );
    // 先插入一个流式占位节点，后续增量会持续覆盖这条消息。
    final initialTree = appendNodeToTree(
      treeState: tree,
      node: assistantMessage,
      parentId: assistantParentId,
    );
    var streamingConversation = conversation.copyWith(
      messageNodes: initialTree.nodes,
      selectedChildByParentId: initialTree.selections,
      updatedAt: timestamp,
      selectedPromptTemplateId: promptTemplate?.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
    var streamingReply = ChatStreamingReply(
      conversationId: streamingConversation.id,
      assistantMessageId: assistantMessage.id,
    );

    // 先把占位消息写入内存和持久层，确保刷新后仍能恢复进度。
    state = state.copyWith(
      conversations: _replaceConversation(streamingConversation),
      isStreaming: true,
      streamingReply: streamingReply,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await _saveAll();

    try {
      final responseBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      var lastUiFlushAt = timestamp.subtract(_streamUiFlushInterval);
      await for (final chunk in _chatClient.streamCompletion(
        modelConfig: modelConfig,
        messages: buildRequestMessages(
          promptTemplate: promptTemplate,
          conversationMessages: requestConversationMessages,
        ),
        reasoningEffort: reasoningEnabled && modelConfig.supportsReasoning
            ? reasoningEffort
            : null,
      )) {
        if (chunk.isEmpty) {
          continue;
        }

        responseBuffer.write(chunk.contentDelta);
        reasoningBuffer.write(chunk.reasoningDelta);
        streamingReply = streamingReply.copyWith(
          content: responseBuffer.toString(),
          reasoningContent: reasoningBuffer.toString(),
        );
        final now = DateTime.now();
        if (now.difference(lastUiFlushAt) < _streamUiFlushInterval) {
          continue;
        }

        _replaceStreamingReplyInMemory(streamingReply);
        lastUiFlushAt = now;
      }

      streamingReply = streamingReply.copyWith(
        content: responseBuffer.toString(),
        reasoningContent: reasoningBuffer.toString(),
      );
      _replaceStreamingReplyInMemory(streamingReply);

      // 持续用最新增量覆盖同一条 assistant 消息，但只在结束时真正写回会话列表。
      final completedConversation = _applyStreamingReplyToConversation(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        isStreaming: false,
      ).copyWith(updatedAt: DateTime.now());

      state = state.copyWith(
        conversations: _replaceConversation(completedConversation),
        isStreaming: false,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      await _saveAll();
      return completedConversation;
    } on ChatCompletionException catch (error) {
      await _handleStreamingFailure(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        assistantMessageId: assistantMessage.id,
        errorMessage: error.message,
      );
    } catch (error, stackTrace) {
      await _handleStreamingFailure(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        assistantMessageId: assistantMessage.id,
        errorMessage: _formatUnexpectedStreamingError(error, stackTrace),
      );
    }

    return null;
  }

  /// 仅刷新流式增量，不去改动完整会话列表。
  void _replaceStreamingReplyInMemory(ChatStreamingReply streamingReply) {
    if (state.streamingReply == streamingReply) {
      return;
    }

    state = state.copyWith(streamingReply: streamingReply, isStreaming: true);
  }

  /// 在会话列表中按 id 覆盖或插入指定会话。
  List<ChatConversation> _replaceConversation(ChatConversation conversation) {
    final conversations = [...state.conversations];
    final index = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );

    if (index == -1) {
      conversations.add(conversation);
    } else {
      conversations[index] = conversation;
    }

    return _sort(conversations);
  }

  /// 按更新时间倒序排列会话。
  List<ChatConversation> _sort(List<ChatConversation> conversations) {
    final sortedConversations = [...conversations];
    sortedConversations.sort((left, right) {
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return List.unmodifiable(sortedConversations);
  }

  /// 只持久化非空会话，避免写入无意义的空草稿。
  Future<void> _saveAll() {
    return _repository.saveAll(
      state.conversations
          .where((conversation) {
            return conversation.hasMessages ||
                (conversation.title?.trim().isNotEmpty ?? false);
          })
          .toList(growable: false),
    );
  }

  /// 选择当前会话对应的模型配置；找不到时回退到首个配置。
  LlmModelConfig? _resolveModelConfig(ChatConversation conversation) {
    final modelConfigs = ref.read(llmModelConfigsProvider);
    if (modelConfigs.isEmpty) {
      return null;
    }

    final defaultModelId = ref.read(chatDefaultsProvider).defaultModelId;
    final defaultModel = modelConfigs.where((config) {
      return config.id == defaultModelId;
    }).firstOrNull;
    if (defaultModel != null) {
      return defaultModel;
    }

    return modelConfigs.where((config) {
          return config.id == conversation.selectedModelId;
        }).firstOrNull ??
        modelConfigs.first;
  }

  /// 选择当前会话对应的 Prompt 模板。
  PromptTemplate? _resolvePromptTemplate(ChatConversation conversation) {
    final promptTemplates = ref.read(promptTemplatesProvider);
    if (promptTemplates.isEmpty) {
      return null;
    }

    return promptTemplates.where((template) {
      return template.id == conversation.selectedPromptTemplateId;
    }).firstOrNull;
  }

  /// 更新错误信息并保留在状态中，供界面展示。
  void _setErrorMessage(String message) {
    state = state.copyWith(errorMessage: message);
  }

  /// 保留原始异常并附加堆栈，方便开发者直接定位问题。
  String _formatUnexpectedStreamingError(Object error, StackTrace stackTrace) {
    final rawError = error.toString();
    final normalizedError = rawError.trim();
    final header = normalizedError.isEmpty
        ? '请求未完成，请检查网络、API URL 或模型配置。'
        : normalizedError;
    return '$header\n\n```text\n$stackTrace\n```';
  }
}
