import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/memory_prompt.dart';
import '../../settings/domain/models/prompt_template.dart';
import 'chat_request_message_builder.dart';
import 'chat_sessions_controller_streaming.dart';
import 'chat_sessions_controller_support.dart';
import 'checkpoint_request_context.dart';
import 'chat_message_tree.dart';
import 'chat_sessions_state.dart';
import '../data/chat_completion_client.dart';
import '../data/chat_conversation_repository.dart';
import '../data/openai_compatible_chat_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

export 'chat_sessions_state.dart';

/// 删除消息时的作用范围。
enum ChatMessageDeletionScope { currentBranch, allBranches }

/// 主入口 provider，暴露完整会话状态和操作接口。
final chatSessionsProvider =
    NotifierProvider<ChatSessionsController, ChatSessionsState>(
      ChatSessionsController.new,
    );

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

/// 是否正在创建检查点。
final isChatCheckpointingProvider = Provider<bool>((ref) {
  return ref.watch(
    chatSessionsProvider.select((state) => state.isCheckpointing),
  );
});

/// 是否有聊天相关请求正在进行。
final isChatBusyProvider = Provider<bool>((ref) {
  return ref.watch(
    chatSessionsProvider.select(
      (state) => state.isStreaming || state.isCheckpointing,
    ),
  );
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
  return applyStreamingReplyToConversation(
    conversation: state.activeConversation,
    streamingReply: state.streamingReply,
  );
});

/// 聊天页面的会话编排器，负责发送、重试、编辑和持久化。
class ChatSessionsController extends Notifier<ChatSessionsState>
    with ChatSessionsControllerSupport, ChatSessionsControllerStreaming {
  @override
  ChatConversationRepository get repository =>
      ref.read(chatConversationRepositoryProvider);

  @override
  ChatCompletionClient get chatClient => ref.read(chatCompletionClientProvider);

  StreamSubscription<ChatCompletionChunk>? _activeStreamingSubscription;
  Completer<ChatConversation?>? _activeStreamingCompleter;
  ChatStreamingReply? _latestStreamingReply;
  bool _streamStopRequested = false;

  @override
  StreamSubscription<ChatCompletionChunk>? get activeStreamingSubscription =>
      _activeStreamingSubscription;

  @override
  set activeStreamingSubscription(
    StreamSubscription<ChatCompletionChunk>? value,
  ) {
    _activeStreamingSubscription = value;
  }

  @override
  Completer<ChatConversation?>? get activeStreamingCompleter =>
      _activeStreamingCompleter;

  @override
  set activeStreamingCompleter(Completer<ChatConversation?>? value) {
    _activeStreamingCompleter = value;
  }

  @override
  ChatStreamingReply? get latestStreamingReply => _latestStreamingReply;

  @override
  set latestStreamingReply(ChatStreamingReply? value) {
    _latestStreamingReply = value;
  }

  @override
  bool get streamStopRequested => _streamStopRequested;

  @override
  set streamStopRequested(bool value) {
    _streamStopRequested = value;
  }

  bool get _isBusy => state.isStreaming || state.isCheckpointing;

  // ── 生命周期 ────────────────────────────────────────────────────────────────

  /// 读取持久化数据并初始化当前会话状态。
  ///
  /// 若数据库为空则自动创建一个新的空白会话作为初始状态。
  @override
  ChatSessionsState build() {
    ref.onDispose(() {
      activeStreamingSubscription?.cancel();
    });
    final conversations = sortConversations(repository.loadAll());
    final initialConversation = conversations.isEmpty
        ? buildEmptyConversation()
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
    if (_isBusy) {
      return;
    }
    final currentConversation = state.activeConversation;
    if (!currentConversation.hasMessages) {
      return;
    }

    final nextConversation = buildEmptyConversation();
    state = state.copyWith(
      conversations: [nextConversation, ...state.conversations],
      activeConversationId: nextConversation.id,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await saveAllConversations();
  }

  /// 选择一个已存在的会话作为活动会话。
  void selectConversation(String id) {
    if (_isBusy) {
      return;
    }
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
    if (_isBusy) {
      return;
    }
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) {
      return;
    }

    await updateActiveConversation(
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
    if (_isBusy) {
      return;
    }
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
      conversations: replaceConversation(
        targetConversation.copyWith(
          title: nextTitle,
          updatedAt: DateTime.now(),
        ),
      ),
      incrementHistoryRevision: true,
    );
    await saveAllConversations();
  }

  /// 删除一组会话，必要时回退到新的空会话。
  Future<void> deleteConversations(Set<String> conversationIds) async {
    if (conversationIds.isEmpty || _isBusy) {
      return;
    }

    final remainingConversations = state.conversations
        .where((conversation) {
          return !conversationIds.contains(conversation.id);
        })
        .toList(growable: false);

    final fallbackConversation =
        remainingConversations.firstOrNull ?? buildEmptyConversation();

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
    await saveAllConversations();
  }

  /// 更新当前会话的模型、前置 Prompt 和思考偏好。
  Future<void> updateActiveConversationPreferences({
    String? selectedModelId,
    String? selectedCheckpointId,
    String? selectedPromptTemplateId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool clearSelectedCheckpointId = false,
    bool clearSelectedPromptTemplateId = false,
  }) {
    if (_isBusy) {
      return Future.value();
    }
    return updateActiveConversation(
      state.activeConversation.copyWith(
        selectedModelId: selectedModelId,
        selectedCheckpointId: selectedCheckpointId,
        selectedPromptTemplateId: selectedPromptTemplateId,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: reasoningEffort,
        clearSelectedCheckpointId: clearSelectedCheckpointId,
        clearSelectedPromptTemplateId: clearSelectedPromptTemplateId,
      ),
    );
  }

  /// 更新当前会话启用的检查点。
  Future<void> selectActiveCheckpoint(String? checkpointId) {
    return updateActiveConversationPreferences(
      selectedCheckpointId: checkpointId,
      clearSelectedCheckpointId: checkpointId == null,
    );
  }

  /// 更新一组消息是否参与后续请求上下文。
  Future<void> setMessagesExcluded({
    required Iterable<String> messageIds,
    required bool excluded,
  }) async {
    if (_isBusy) {
      return;
    }

    final currentConversation = state.activeConversation;
    final validMessageIds = currentConversation.messageNodes
        .map((message) => message.id)
        .toSet();
    final targetIds = messageIds.where(validMessageIds.contains).toSet();
    if (targetIds.isEmpty) {
      return;
    }

    final nextExcludedIds = Set<String>.from(
      currentConversation.excludedMessageIds,
    );
    if (excluded) {
      nextExcludedIds.addAll(targetIds);
    } else {
      nextExcludedIds.removeAll(targetIds);
    }

    if (nextExcludedIds.length ==
            currentConversation.excludedMessageIds.length &&
        nextExcludedIds.containsAll(currentConversation.excludedMessageIds)) {
      return;
    }

    final orderedExcludedIds = currentConversation.messageNodes
        .where((message) => nextExcludedIds.contains(message.id))
        .map((message) => message.id)
        .toList(growable: false);
    await updateActiveConversation(
      currentConversation.copyWith(excludedMessageIds: orderedExcludedIds),
    );
  }

  /// 基于当前上下文创建一个新的检查点。
  Future<ChatCheckpoint> createCheckpoint({
    required LlmModelConfig modelConfig,
    required MemoryPrompt memoryPrompt,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    String? sourceCheckpointId,
  }) async {
    if (_isBusy) {
      throw const ChatCompletionException('当前仍有请求在进行，请稍后再试。');
    }

    final currentConversation = state.activeConversation;
    final promptTemplate = resolvePromptTemplate(currentConversation);
    final sourceContext = resolveCheckpointRequestContext(
      checkpoints: currentConversation.checkpoints,
      selectedCheckpointId: sourceCheckpointId,
      conversationMessages: currentConversation.messages,
    );
    if (sourceCheckpointId != null && sourceContext.checkpointChain.isEmpty) {
      throw const ChatCompletionException('所选检查点与当前分支不兼容，请重新选择。');
    }

    final summaryMessages = sourceCheckpointId == null
        ? currentConversation.messages
        : sourceContext.tailMessages;
    if (summaryMessages.isEmpty) {
      throw const ChatCompletionException('当前没有可用于创建检查点的新上下文。');
    }

    state = state.copyWith(isCheckpointing: true, clearErrorMessage: true);
    try {
      final result = await chatClient.complete(
        modelConfig: modelConfig,
        messages: buildCheckpointSummaryMessages(
          memoryPrompt: memoryPrompt,
          conversationMessages: summaryMessages,
          checkpointChain: sourceContext.checkpointChain,
          promptTemplate: promptTemplate,
          filter: ExcludeByIdMessageFilter(
            currentConversation.excludedMessageIds.toSet(),
          ),
        ),
        reasoningEffort: reasoningEnabled && modelConfig.supportsReasoning
            ? reasoningEffort
            : null,
      );
      final checkpointContent = result.content.trim();
      if (checkpointContent.isEmpty) {
        throw const ChatCompletionException('模型没有返回可用的检查点内容。');
      }

      final now = DateTime.now();
      final nextCheckpoint = ChatCheckpoint(
        id: generateEntityId(),
        title: buildNextCheckpointTitle(currentConversation.checkpoints),
        content: checkpointContent,
        createdAt: now,
        parentCheckpointId: sourceContext.activeCheckpoint?.id,
        coveredUntilMessageId: currentConversation.messages.lastOrNull?.id,
        sourceMemoryPromptName: memoryPrompt.name,
      );
      final nextConversation = currentConversation.copyWith(
        checkpoints: [...currentConversation.checkpoints, nextCheckpoint],
        updatedAt: now,
      );

      state = state.copyWith(
        conversations: replaceConversation(nextConversation),
        isCheckpointing: false,
        clearErrorMessage: true,
        incrementHistoryRevision: true,
      );
      await saveAllConversations();
      return nextCheckpoint;
    } catch (_) {
      state = state.copyWith(isCheckpointing: false);
      rethrow;
    }
  }

  /// 切换某个父节点下的选中消息版本。
  Future<void> selectMessageVersion({
    required String parentId,
    required String messageId,
  }) async {
    if (_isBusy) {
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
    await updateActiveConversation(
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
    if (_isBusy) {
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

    final modelConfig = resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      setErrorMessage('无法重算：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = resolvePromptTemplate(currentConversation);
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
    final checkpointContext = resolveCheckpointContext(
      conversation: rebuiltConversation,
      conversationMessages: rebuiltConversation.messages,
    );
    await streamAssistantReply(
      conversation: rebuiltConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: branchUserMessage.id,
      reasoningEnabled: rebuiltConversation.reasoningEnabled,
      reasoningEffort: rebuiltConversation.reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpoint?.title ?? '',
    );
  }

  /// 重新请求当前对话中最新的一条模型回复。
  Future<void> retryLatestAssistant() async {
    if (_isBusy) {
      return;
    }

    final currentConversation = state.activeConversation;
    final activePath = currentConversation.messages;
    final latestMessage = activePath.lastOrNull;
    if (latestMessage == null) {
      setErrorMessage('只能重试当前对话中的最新模型回复。');
      return;
    }

    final modelConfig = resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      setErrorMessage('无法重试：当前对话没有可用模型，请先检查模型设置。');
      return;
    }

    final promptTemplate = resolvePromptTemplate(currentConversation);
    if (latestMessage.role == ChatMessageRole.user &&
        state.errorMessage != null) {
      final checkpointContext = resolveCheckpointContext(
        conversation: currentConversation,
        conversationMessages: activePath,
      );
      await streamAssistantReply(
        conversation: currentConversation.copyWith(updatedAt: DateTime.now()),
        modelConfig: modelConfig,
        promptTemplate: promptTemplate,
        requestConversationMessages: checkpointContext.tailMessages,
        requestCheckpointChain: checkpointContext.checkpointChain,
        parentMessageId: latestMessage.id,
        reasoningEnabled: currentConversation.reasoningEnabled,
        reasoningEffort: currentConversation.reasoningEffort,
        appliedCheckpointTitle: checkpointContext.activeCheckpoint?.title ?? '',
      );
      return;
    }

    final latestAssistantIndex = activePath.lastIndexWhere((message) {
      return message.role == ChatMessageRole.assistant;
    });
    if (latestAssistantIndex == -1 ||
        latestAssistantIndex != activePath.length - 1) {
      setErrorMessage('只能重试当前对话中的最新模型回复。');
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
      conversations: replaceConversation(baseConversation),
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await saveAllConversations();

    final checkpointContext = resolveCheckpointContext(
      conversation: baseConversation,
      conversationMessages: requestMessages,
    );

    await streamAssistantReply(
      conversation: baseConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: parentId == rootConversationParentId ? null : parentId,
      reasoningEnabled: baseConversation.reasoningEnabled,
      reasoningEffort: baseConversation.reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpoint?.title ?? '',
    );
  }

  /// 发送新消息并触发模型流式回复。
  Future<void> sendMessage({
    required String content,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    List<UserMessageSegment> userMessageSegments = const [],
  }) async {
    if (_isBusy) {
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
      userMessageSegments: userMessageSegments,
    );
    final pendingNodes = [...tree.nodes, userMessage];
    final pendingSelections = Map<String, String>.from(tree.selections);
    pendingSelections[parentId ?? rootConversationParentId] = userMessage.id;

    final pendingConversation = currentConversation.copyWith(
      messageNodes: pendingNodes,
      selectedChildByParentId: pendingSelections,
      updatedAt: timestamp,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
    final checkpointContext = resolveCheckpointContext(
      conversation: pendingConversation,
      conversationMessages: pendingConversation.messages,
    );
    await streamAssistantReply(
      conversation: pendingConversation,
      modelConfig: modelConfig,
      promptTemplate: promptTemplate,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: userMessage.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpoint?.title ?? '',
    );
  }

  /// 删除一条当前可见消息；当 [scope] 为全部版本时，会删除同父节点下所有兄弟分支。
  Future<void> deleteMessage({
    required String messageId,
    required ChatMessageDeletionScope scope,
  }) async {
    if (_isBusy) {
      return;
    }

    final currentConversation = state.activeConversation;
    final tree = resolveMessageTreeState(currentConversation);
    final targetMessage = tree.nodes.where((message) {
      return message.id == messageId;
    }).firstOrNull;
    if (targetMessage == null) {
      return;
    }

    final parentId = targetMessage.parentId ?? rootConversationParentId;
    final siblingIds = tree.nodes
        .where((message) {
          return (message.parentId ?? rootConversationParentId) == parentId;
        })
        .map((message) => message.id)
        .toList(growable: false);
    final removedIds = scope == ChatMessageDeletionScope.allBranches
        ? siblingIds
        : [messageId];

    var nextTree = tree;
    for (final removedId in removedIds) {
      nextTree = removeNodeFromTree(treeState: nextTree, nodeId: removedId);
    }

    final remainingSiblings = nextTree.nodes
        .where((message) {
          return (message.parentId ?? rootConversationParentId) == parentId;
        })
        .toList(growable: false);
    final nextSelections = Map<String, String>.from(nextTree.selections);
    if (remainingSiblings.isEmpty) {
      nextSelections.remove(parentId);
    } else {
      nextSelections[parentId] = remainingSiblings.first.id;
    }

    await updateActiveConversation(
      currentConversation.copyWith(
        messageNodes: nextTree.nodes,
        selectedChildByParentId: nextSelections,
        updatedAt: DateTime.now(),
        excludedMessageIds: currentConversation.excludedMessageIds
            .where((id) {
              return nextTree.nodes.any((message) => message.id == id);
            })
            .toList(growable: false),
      ),
    );
  }
}
