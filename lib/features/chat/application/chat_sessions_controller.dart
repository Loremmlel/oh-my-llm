import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/auto_retry_settings_controller.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/memory_prompt.dart';
import '../../settings/domain/models/preset_prompt.dart';
import 'chat_generation_coordinator.dart';
import 'chat_generation_lifecycle.dart';
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
import '../domain/models/chat_conversation_summary.dart';
import '../domain/chat_error_messages.dart';
import '../domain/chat_message_parent.dart';
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

/// 全量会话的轻量摘要列表，供侧栏分组渲染。
final chatConversationSummariesProvider =
    Provider<List<ChatConversationSummary>>((ref) {
      return ref.watch(
        chatSessionsProvider.select((state) => state.conversationSummaries),
      );
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
      (state) =>
          state.isStreaming ||
          state.isCheckpointing ||
          state.isAutoRetryWaiting,
    ),
  );
});

/// 当前错误提示文字，无错误时为 `null`（仅在错误状态变化时重建）。
final chatErrorMessageProvider = Provider<String?>((ref) {
  return ref.watch(chatSessionsProvider.select((state) => state.errorMessage));
});

/// 当前错误提示所关联的 assistant 消息 ID。
final chatErrorMessageAssistantIdProvider = Provider<String?>((ref) {
  return ref.watch(
    chatSessionsProvider.select((state) => state.errorMessageAssistantId),
  );
});

/// 当前空回复提示所关联的 assistant 消息 ID。
final chatEmptyReplyAssistantIdProvider = Provider<String?>((ref) {
  return ref.watch(
    chatSessionsProvider.select((state) => state.emptyReplyAssistantId),
  );
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
///
/// 消息列表消费方（如 [ChatMessagesPanel]）必须监听此 provider 以逐 token
/// 刷新；配置字段（模型/预设等）读取虽也走此 provider，但相关 O(n) 计算
/// 已在消费侧用指纹 memoize 缓解，无需单独的配置视图 provider。
final activeChatConversationProvider = Provider<ChatConversation>((ref) {
  final state = ref.watch(chatSessionsProvider);
  return applyStreamingReplyToConversation(
    conversation: state.activeConversation,
    streamingReply: state.streamingReply,
  );
});

/// 聊天页面的会话编排器，负责发送、重试、编辑和持久化。
class ChatSessionsController extends Notifier<ChatSessionsState>
    with ChatSessionsControllerSupport, ChatSessionsControllerStreaming
    implements ChatGenerationObserver {
  @override
  ChatConversationRepository get repository =>
      ref.read(chatConversationRepositoryProvider);

  @override
  ChatCompletionClient get chatClient => ref.read(chatCompletionClientProvider);

  StreamSubscription<ChatCompletionChunk>? _activeStreamingSubscription;
  Completer<ChatConversation?>? _activeStreamingCompleter;
  ChatStreamingReply? _latestStreamingReply;
  bool _streamStopRequested = false;
  bool _autoRetryCancelled = false;
  int _requestGeneration = 0;
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

  @override
  bool get autoRetryCancelled => _autoRetryCancelled;

  @override
  set autoRetryCancelled(bool value) {
    _autoRetryCancelled = value;
  }

  @override
  int get requestGeneration => _requestGeneration;

  @override
  set requestGeneration(int value) {
    _requestGeneration = value;
  }

  // ── ChatGenerationCoordinator 桥接字段（Task 6 清理） ─────────────────────

  ChatGenerationCoordinator? _generationCoordinator;

  /// 懒初始化协调器：首次发送时才读取 chatClient，避免 build() 阶段触发
  /// chatCompletionClientProvider（连带 appNetworkLogger）在未发送消息的
  /// 场景（如 widget bootstrap）下产生副作用。
  ChatGenerationCoordinator get _coordinator {
    _generationCoordinator ??= ChatGenerationCoordinator(client: chatClient);
    return _generationCoordinator!;
  }

  Completer<ChatConversation?>? _coordinatorCompleter;

  /// 当前活跃 generation 的 id。用于丢弃上一轮 _handleGenerationEvent 在 await
  /// 让出后迟到的残留事件，并阻止其 _cleanupCoordinatorBridge 清错新字段。
  int? _coordinatorGenerationId;
  ChatConversation? _coordinatorStreamingConversation;
  ChatMessage? _coordinatorAssistantMessage;
  ChatStreamingReply? _coordinatorStreamingReply;
  final _coordinatorResponseBuffer = StringBuffer();
  final _coordinatorReasoningBuffer = StringBuffer();
  var _coordinatorLastUiFlushAt = DateTime(2000);
  ChatRetryPolicy? _coordinatorRetryPolicy;

  bool get _isBusy =>
      state.isStreaming || state.isCheckpointing || state.isAutoRetryWaiting;

  // ── 生命周期 ────────────────────────────────────────────────────────────────

  /// 读取持久化数据并初始化当前会话状态。
  ///
  /// 若数据库为空则自动创建一个新的空白会话作为初始状态。
  @override
  ChatSessionsState build() {
    ref.onDispose(() {
      // 先让 coordinator invalidate token + cancel 等待器/订阅，再清旧路径
      // streaming subscription；coordinator 内部已用 _disposed 守卫拦截迟到回调，
      // 不会在迟到回调中重置已创建的新 coordinator/run。
      _generationCoordinator?.dispose();
      activeStreamingSubscription?.cancel();
    });

    final summaries = repository.loadHistorySummaries();

    if (summaries.isEmpty) {
      final initialConversation = buildEmptyConversation();
      return ChatSessionsState(
        conversations: [initialConversation],
        conversationSummaries: const [],
        activeConversationId: initialConversation.id,
      );
    }

    final activeConversation = repository.loadConversation(summaries.first.id);

    if (activeConversation == null) {
      final fallback = buildEmptyConversation();
      return ChatSessionsState(
        conversations: [fallback],
        conversationSummaries: summaries,
        activeConversationId: fallback.id,
      );
    }

    return ChatSessionsState(
      conversations: [activeConversation],
      conversationSummaries: summaries,
      activeConversationId: activeConversation.id,
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
      clearEmptyReply: true,
      incrementHistoryRevision: true,
    );
    saveConversation(currentConversation);
  }

  /// 选择一个已存在的会话作为活动会话。
  void selectConversation(String id) {
    if (_isBusy) {
      return;
    }

    final summaryExists = state.conversationSummaries.any((s) => s.id == id);
    if (!summaryExists || state.activeConversationId == id) {
      return;
    }

    final isLoaded = state.conversations.any((c) => c.id == id);
    if (!isLoaded) {
      final fullConv = repository.loadConversation(id);
      if (fullConv == null) {
        return;
      }
      state = state.copyWith(
        conversations: [fullConv, ...state.conversations],
        activeConversationId: id,
        clearErrorMessage: true,
        clearEmptyReply: true,
      );
    } else {
      state = state.copyWith(
        activeConversationId: id,
        clearErrorMessage: true,
        clearEmptyReply: true,
      );
    }
  }

  /// 选择会话并导航到指定消息，调整分支路径使目标消息可见。
  void selectConversationAndNavigateToMessage(
    String conversationId, {
    String? messageId,
  }) {
    selectConversation(conversationId);

    if (messageId == null) return;

    final conversation = state.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conversation == null) return;

    if (!conversation.messageNodes.any((m) => m.id == messageId)) return;

    final ancestorPath = _resolveAncestorPath(
      conversation.messageNodes,
      targetId: messageId,
    );
    if (ancestorPath.isEmpty) return;

    final nextSelections = Map<String, String>.from(
      conversation.selectedChildByParentId,
    );
    for (var i = 0; i < ancestorPath.length; i += 1) {
      final parentId = i == 0 ? rootConversationParentId : ancestorPath[i - 1];
      nextSelections[parentId] = ancestorPath[i];
    }

    final updatedConversation = conversation.copyWith(
      selectedChildByParentId: nextSelections,
      updatedAt: conversation.updatedAt,
    );
    state = state.copyWith(
      conversations: replaceConversation(updatedConversation),
      pendingScrollToMessageId: messageId,
    );
    saveConversation(updatedConversation);
  }

  void clearPendingScrollToMessageId() {
    state = state.copyWith(clearPendingScrollToMessageId: true);
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

    updateActiveConversation(
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

    var targetConversation = state.conversations.where((conversation) {
      return conversation.id == conversationId;
    }).firstOrNull;

    if (targetConversation == null) {
      final loaded = repository.loadConversation(conversationId);
      if (loaded == null) {
        return;
      }
      targetConversation = loaded;
    }

    final renamed = targetConversation.copyWith(
      title: nextTitle,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      conversations: replaceConversation(renamed),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(renamed),
      ),
      incrementHistoryRevision: true,
    );
    saveConversation(renamed);
  }

  /// 删除一组会话，必要时回退到新的空会话。
  Future<void> deleteConversations(Set<String> conversationIds) async {
    if (conversationIds.isEmpty || _isBusy) {
      return;
    }

    await repository.deleteConversations(conversationIds.toList());

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
      conversationSummaries: state.conversationSummaries
          .where((s) => !conversationIds.contains(s.id))
          .toList(growable: false),
      activeConversationId:
          remainingConversations.any((conversation) {
            return conversation.id == state.activeConversationId;
          })
          ? state.activeConversationId
          : fallbackConversation.id,
      clearErrorMessage: true,
      clearEmptyReply: true,
      incrementHistoryRevision: true,
    );
  }

  /// 更新当前会话的模型、前置 Prompt 和思考偏好。
  ///
  /// 这些字段仅影响下次发送的请求构造，不干预进行中的流式请求，
  /// 因此不做忙碌态守卫；流式期间写入后，流式落盘时会合并保留这些改动。
  void updateActiveConversationPreferences({
    String? selectedModelId,
    String? selectedCheckpointId,
    String? selectedPresetPromptId,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    bool? autoRetryEnabled,
    bool clearSelectedCheckpointId = false,
    bool clearSelectedPresetPromptId = false,
  }) {
    updateActiveConversation(
      state.activeConversation.copyWith(
        selectedModelId: selectedModelId,
        selectedCheckpointId: selectedCheckpointId,
        selectedPresetPromptId: selectedPresetPromptId,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: reasoningEffort,
        autoRetryEnabled: autoRetryEnabled,
        clearSelectedCheckpointId: clearSelectedCheckpointId,
        clearSelectedPresetPromptId: clearSelectedPresetPromptId,
      ),
      incrementHistoryRevision: false,
    );
  }

  /// 更新当前会话启用的检查点。
  void selectActiveCheckpoint(String? checkpointId) {
    return updateActiveConversationPreferences(
      selectedCheckpointId: checkpointId,
      clearSelectedCheckpointId: checkpointId == null,
    );
  }

  /// 更新一组消息是否参与后续请求上下文。
  ///
  /// 标记排除状态只影响下次发送的请求上下文，不会干预进行中的流式请求，
  /// 因此不做忙碌态守卫。
  Future<void> setMessagesExcluded({
    required Iterable<String> messageIds,
    required bool excluded,
  }) async {
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
    updateActiveConversation(
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
      throw const ChatCompletionException(ChatErrorMessages.busy);
    }

    final currentConversation = state.activeConversation;
    final presetPrompt = resolvePresetPrompt(currentConversation);
    final sourceContext = resolveCheckpointRequestContext(
      checkpoints: currentConversation.checkpoints,
      selectedCheckpointId: sourceCheckpointId,
      conversationMessages: currentConversation.messages,
    );
    if (sourceCheckpointId != null && sourceContext.checkpointChain.isEmpty) {
      throw const ChatCompletionException(
        ChatErrorMessages.incompatibleCheckpoint,
      );
    }

    final summaryMessages = sourceCheckpointId == null
        ? currentConversation.messages
        : sourceContext.tailMessages;
    if (summaryMessages.isEmpty) {
      throw const ChatCompletionException(
        ChatErrorMessages.noCheckpointContext,
      );
    }

    state = state.copyWith(
      isCheckpointing: true,
      clearErrorMessage: true,
      clearEmptyReply: true,
    );
    try {
      final result = await chatClient.complete(
        modelConfig: modelConfig,
        messages: buildCheckpointSummaryMessages(
          memoryPrompt: memoryPrompt,
          conversationMessages: summaryMessages,
          checkpointChain: sourceContext.checkpointChain,
          presetPrompt: presetPrompt,
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
        conversationSummaries: replaceOrAddSummary(
          state.conversationSummaries,
          summaryFromConversation(nextConversation),
        ),
        isCheckpointing: false,
        clearErrorMessage: true,
        clearEmptyReply: true,
        incrementHistoryRevision: true,
      );
      saveConversation(nextConversation);
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
          return node.effectiveParentId == parentId;
        })
        .toList(growable: false);
    final hasTarget = siblings.any((node) => node.id == messageId);
    if (!hasTarget) {
      return;
    }

    final nextSelections = Map<String, String>.from(tree.selections);
    nextSelections[parentId] = messageId;
    updateActiveConversation(
      currentConversation.copyWith(
        messageNodes: tree.nodes,
        selectedChildByParentId: nextSelections,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 根据对话的 autoRetryEnabled 标志，选择直接发送或自动重试发送。
  Future<void> _sendWithOptionalAutoRetry({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PresetPrompt? presetPrompt,
    required List<ChatMessage> requestConversationMessages,
    required List<ChatCheckpoint> requestCheckpointChain,
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    required String appliedCheckpointTitle,
    Duration? retryDelay,
  }) async {
    await _runGenerationViaCoordinator(
      conversation: conversation,
      modelConfig: modelConfig,
      presetPrompt: presetPrompt,
      requestConversationMessages: requestConversationMessages,
      requestCheckpointChain: requestCheckpointChain,
      parentMessageId: parentMessageId,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      appliedCheckpointTitle: appliedCheckpointTitle,
      retryDelay: retryDelay,
    );
  }

  /// 通过 [ChatGenerationCoordinator] 执行一次无自动重试的发送。
  ///
  /// 复制 [streamAssistantReply] 的准备阶段逻辑（创建占位消息、追加到树、
  /// 设 streamingConversation、更新 state），然后构建 [ChatGenerationRequest]
  /// 调 [ChatGenerationCoordinator.start]，返回 completer 的 future。
  Future<ChatConversation?> _runGenerationViaCoordinator({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PresetPrompt? presetPrompt,
    required List<ChatMessage> requestConversationMessages,
    List<ChatCheckpoint> requestCheckpointChain = const [],
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    String appliedCheckpointTitle = '',
    Duration? retryDelay,
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
      appliedCheckpointTitle: appliedCheckpointTitle,
    );
    final initialTree = appendNodeToTree(
      treeState: tree,
      node: assistantMessage,
      parentId: assistantParentId,
    );
    final streamingConversation = conversation.copyWith(
      messageNodes: initialTree.nodes,
      selectedChildByParentId: initialTree.selections,
      updatedAt: timestamp,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
    );
    final streamingReply = ChatStreamingReply(
      conversationId: streamingConversation.id,
      assistantMessageId: assistantMessage.id,
    );
    final completer = Completer<ChatConversation?>();

    // 初始化桥接字段，供 _handleGenerationEvent 使用。
    // activeStreamingCompleter 与 _coordinatorCompleter 指向同一 completer：
    // finishGenerationSuccess 内部靠 completeActiveStreaming 完成它，复用旧
    // streaming session 字段，避免两条路径的完成/清理逻辑割裂导致 future 挂死。
    _coordinatorCompleter = completer;
    activeStreamingCompleter = completer;
    // 重置上一轮 stopStreaming 置位的标志，对应旧路径 streamAssistantReply
    // 的 streamStopRequested = false，保持「下次流式开始时重置」的公共契约。
    streamStopRequested = false;
    autoRetryCancelled = false;
    _coordinatorStreamingConversation = streamingConversation;
    _coordinatorAssistantMessage = assistantMessage;
    _coordinatorStreamingReply = streamingReply;
    _coordinatorResponseBuffer.clear();
    _coordinatorReasoningBuffer.clear();
    _coordinatorLastUiFlushAt = timestamp.subtract(
      ChatSessionsControllerStreaming.streamUiFlushInterval,
    );
    _coordinatorRetryPolicy = ChatRetryPolicy.fromSnapshot(
      conversationAutoRetryEnabled: conversation.autoRetryEnabled,
      settings: ref.read(autoRetrySettingsProvider),
    );

    state = state.copyWith(
      conversations: replaceConversation(streamingConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(streamingConversation),
      ),
      isStreaming: true,
      streamingReply: streamingReply,
      clearErrorMessage: true,
      clearEmptyReply: true,
      incrementHistoryRevision: true,
    );
    // pending save：占位 assistant 消息落盘。await durable，失败则在发起任何
    // 网络请求前中止 generation（不 _coordinator.start），避免假成功与重复请求。
    final pendingSaveError = await saveConversationDurable(
      streamingConversation,
    );
    if (pendingSaveError != null) {
      _handleGenerationPersistenceFailure(
        generationId: null,
        error: pendingSaveError,
      );
      return completer.future;
    }

    final request = ChatGenerationRequest(
      conversationId: streamingConversation.id,
      assistantMessageId: assistantMessage.id,
      parentMessageId: parentMessageId,
      modelConfig: modelConfig,
      messages: buildRequestMessages(
        presetPrompt: presetPrompt,
        conversationMessages: requestConversationMessages,
        checkpointChain: requestCheckpointChain,
        filter: ExcludeByIdMessageFilter(
          conversation.excludedMessageIds.toSet(),
        ),
      ),
      reasoningEffort: reasoningEnabled && modelConfig.supportsReasoning
          ? reasoningEffort
          : null,
      retryPolicy: _coordinatorRetryPolicy!,
      streamIdleTimeout: _coordinatorRetryPolicy!.retryOnTimeout
          ? _coordinatorRetryPolicy!.timeout
          : null,
      retryDelay: retryDelay,
    );
    _coordinator.start(request, this);

    return completer.future;
  }

  /// 停止通过 coordinator 进行的 generation。
  @override
  Future<ChatConversation?> stopStreaming() async {
    final coordinator = _generationCoordinator;
    if (coordinator != null && coordinator.hasActive) {
      // 与旧路径 stopStreaming 保持一致的副作用：streamStopRequested 供延迟
      // 回调守卫与公共契约使用，autoRetryCancelled 防止残留等待态干扰下一轮。
      streamStopRequested = true;
      autoRetryCancelled = true;
      coordinator.stop();
      // 事件已同步投递，state 已更新。
      return state.activeConversation;
    }
    return super.stopStreaming();
  }

  // ── ChatGenerationObserver ───────────────────────────────────────────────

  @override
  void onGenerationEvent(ChatGenerationEvent event) {
    // Started 确立当前 generation；其余事件若 generationId 与当前活跃不一致，
    // 说明是上一轮 _handleGenerationEvent 在 await 让出后、新一轮已覆盖字段
    // 期间迟到的残留事件，丢弃以免读写错乱（A 的 async 残留 vs B 的新字段）。
    if (event is! ChatGenerationStarted &&
        event.generationId != _coordinatorGenerationId) {
      return;
    }
    _handleGenerationEvent(event);
  }

  Future<void> _handleGenerationEvent(ChatGenerationEvent event) async {
    switch (event) {
      case ChatGenerationStarted():
        // 确立本次 generation 的 id，供后续事件比对与 _cleanupCoordinatorBridge 守卫。
        _coordinatorGenerationId = event.generationId;
        // 每轮 attempt 重建空白 streamingReply：ChatStreamingReply.copyWith 用
        // `finishReason ?? this.finishReason`，传 null 不清空，若直接复用上一轮
        // 的 _coordinatorStreamingReply，上一轮的异常 finish_reason（如
        // content_filter）会残留到本轮，导致 finishGenerationSuccess 误走 branch 3
        // 触发无限重试。旧 streamAssistantReply 每次 attempt 新建 streamingReply，
        // 这里等价。conversationId/assistantMessageId 不变。
        _coordinatorStreamingReply = ChatStreamingReply(
          conversationId: _coordinatorStreamingConversation!.id,
          assistantMessageId: _coordinatorAssistantMessage!.id,
        );
        // 重试 attempt 开始：退出等待态（首次 attempt 本就 false，no-op），
        // 并清除上一轮 attempt 的 inline error/empty 标记--对应旧
        // sendMessageWithAutoRetry 循环顶部 clearErrorMessage/clearEmptyReply，
        // 否则上一轮的错误文案会残留到重试成功后仍显示。
        state = state.copyWith(
          isAutoRetryWaiting: false,
          streamingReply: _coordinatorStreamingReply,
          clearErrorMessage: true,
          clearEmptyReply: true,
        );
        // 重置缓冲区确保不会混入旧 attempt 残留。
        _coordinatorResponseBuffer.clear();
        _coordinatorReasoningBuffer.clear();
        _coordinatorLastUiFlushAt = DateTime.now().subtract(
          ChatSessionsControllerStreaming.streamUiFlushInterval,
        );

      case ChatGenerationChunk():
        _coordinatorResponseBuffer.write(event.contentDelta);
        _coordinatorReasoningBuffer.write(event.reasoningDelta);
        _coordinatorStreamingReply = _coordinatorStreamingReply?.copyWith(
          content: _coordinatorResponseBuffer.toString(),
          reasoningContent: _coordinatorReasoningBuffer.toString(),
          finishReason:
              event.finishReason ?? _coordinatorStreamingReply?.finishReason,
        );
        final now = DateTime.now();
        if (now.difference(_coordinatorLastUiFlushAt) <
            ChatSessionsControllerStreaming.streamUiFlushInterval) {
          return;
        }
        if (_coordinatorStreamingReply != null) {
          replaceStreamingReplyInMemory(
            _coordinatorStreamingReply!.copyWith(
              content: applyOutputProcessing(
                _coordinatorStreamingReply!.content,
              ),
            ),
          );
        }
        _coordinatorLastUiFlushAt = now;

      case ChatGenerationAttemptCompleted(
        outcome: final ChatGenerationSuccess outcome,
      ):
        // 更新 streamingReply 为最终内容，然后走分支 2/4/5。
        _coordinatorStreamingReply = _coordinatorStreamingReply?.copyWith(
          content: outcome.content,
          reasoningContent: outcome.reasoningContent,
          finishReason: outcome.finishReason,
        );
        if (_coordinatorStreamingReply != null) {
          replaceStreamingReplyInMemory(_coordinatorStreamingReply!);
        }
        final successResult = await finishGenerationSuccess(
          streamingConversation: _coordinatorStreamingConversation!,
          assistantMessage: _coordinatorAssistantMessage!,
          streamingReply: _coordinatorStreamingReply!,
          retryOnAbnormalFinishReason:
              _coordinatorRetryPolicy?.retryOnAbnormalFinishReason ?? false,
          skipEmptyCheck: true,
        );
        await _handleGenerationDecision(event.generationId, successResult);

      case ChatGenerationAttemptCompleted(
        outcome: final ChatGenerationEmptyReply outcome,
      ):
        // 搬分支 1：空回复处理。
        _coordinatorStreamingReply = _coordinatorStreamingReply?.copyWith(
          finishReason: outcome.finishReason,
        );
        if (_coordinatorStreamingReply != null) {
          replaceStreamingReplyInMemory(_coordinatorStreamingReply!);
        }
        final emptyResult = await finishGenerationSuccess(
          streamingConversation: _coordinatorStreamingConversation!,
          assistantMessage: _coordinatorAssistantMessage!,
          streamingReply: _coordinatorStreamingReply!,
          retryOnAbnormalFinishReason:
              _coordinatorRetryPolicy?.retryOnAbnormalFinishReason ?? false,
        );
        await _handleGenerationDecision(event.generationId, emptyResult);

      case ChatGenerationAttemptFailed(
        outcome: final ChatGenerationFailure outcome,
      ):
        // 搬 completeWithError：先 complete null，再用桥接字段调用
        // handleStreamingFailure，清理必须在 await 之后——否则
        // _coordinatorStreamingConversation 等已被置 null 会导致空指针崩溃。
        await finishGenerationError(
          streamingConversation: _coordinatorStreamingConversation!,
          streamingReply: _coordinatorStreamingReply,
          assistantMessage: _coordinatorAssistantMessage!,
          error: outcome.error,
          stackTrace: outcome.stackTrace ?? StackTrace.empty,
        );
        await _handleGenerationDecision(event.generationId, null);

      case ChatGenerationStopped():
        // 部分内容落盘。
        final streamingReply = _coordinatorStreamingReply?.copyWith(
          content: _coordinatorResponseBuffer.toString(),
          reasoningContent: _coordinatorReasoningBuffer.toString(),
        );
        final wasStreaming = state.isStreaming;
        final shouldSave = wasStreaming || streamingReply != null;
        final stoppedConversation = shouldSave
            ? buildConversationAfterStreamingInterrupt(
                conversation: state.activeConversation,
                streamingReply: streamingReply,
              )
            : state.activeConversation;
        final assistantMessageId = streamingReply?.assistantMessageId;
        final isEmpty =
            streamingReply == null ||
            (streamingReply.content.trim().isEmpty &&
                streamingReply.reasoningContent.trim().isEmpty);
        final shouldMarkEmptyReply = isEmpty && assistantMessageId != null;

        state = state.copyWith(
          conversations: replaceConversation(stoppedConversation),
          conversationSummaries: replaceOrAddSummary(
            state.conversationSummaries,
            summaryFromConversation(stoppedConversation),
          ),
          isStreaming: false,
          isAutoRetryWaiting: false,
          clearAutoRetryCount: true,
          clearStreamingReply: true,
          incrementHistoryRevision: true,
          emptyReplyAssistantId: shouldMarkEmptyReply
              ? assistantMessageId
              : null,
          errorMessage: shouldMarkEmptyReply
              ? ChatErrorMessages.stoppedByUser
              : null,
          errorMessageAssistantId: shouldMarkEmptyReply
              ? assistantMessageId
              : null,
          clearErrorMessage: !shouldMarkEmptyReply,
          clearEmptyReply: !shouldMarkEmptyReply,
        );
        if (shouldSave) {
          // stop 落盘 durable。generation 已 terminal（Cancelled 紧随其后 complete
          // completer + cleanup），此处仅感知落盘失败并投影 persistence 错误；
          // 守卫避免 await 让出后新 generation 已起时误覆盖其状态。
          final saveError = await saveConversationDurable(stoppedConversation);
          if (saveError != null &&
              !state.isStreaming &&
              state.activeConversation.id == stoppedConversation.id) {
            state = state.copyWith(
              errorMessage: ChatErrorMessages.persistenceFailed,
              errorMessageAssistantId: assistantMessageId,
              clearEmptyReply: true,
            );
          }
        }

      case ChatGenerationCancelledEvent():
        final completer = _coordinatorCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(null);
        }
        _cleanupCoordinatorBridge(event.generationId);

      case ChatGenerationRetryScheduled():
        // 进入重试等待窗口：标记等待态，累加重试计数。
        // autoRetryCount = nextAttempt - 1（首次 attempt 为 1，首次重试 nextAttempt=2 -> count=1）。
        state = state.copyWith(
          isAutoRetryWaiting: true,
          autoRetryCount: event.nextAttempt - 1,
        );

      case ChatGenerationPersistenceFailedEvent():
        // persistence 失败由 controller 在 _handleGenerationDecision /
        // _runGenerationViaCoordinator 检测 save Future 时直接处理
        // （markPersistenceFailure + inline error），不经 event 往返；
        // coordinator 当前不投递此事件，保留类型供将来 coordinator 自检场景。
        break;

      default:
        // coordinator 理论上不会投递其他组合，此处兜底。
        break;
    }
  }

  /// attempt 终态后的重试/终态决策。
  ///
  /// [result] 非 null 表示终态成功（内存已更新的会话），null 表示重试信号
  /// （空回复 / 异常 finish 未清空 / 失败）。两类都先 durable 落盘：成功终态
  /// 落盘 result，重试信号落盘本次 attempt 的占位（state.activeConversation）。
  /// 落盘失败 -> [persistenceFailed] 终态（不假成功、不重试、不重复请求）。
  ///
  /// 落盘成功后：成功终态完成 completer(result)；重试信号下若
  /// [ChatGenerationCoordinator.scheduleRetry] 返回 false（autoRetry 关、达上限
  /// 或不可重试），按终态 null 完成并清理；否则保持 completer 开启，等待新 attempt。
  Future<void> _handleGenerationDecision(
    int generationId,
    ChatConversation? result,
  ) async {
    if (result != null) {
      // 成功终态：durable 落盘。
      final saveError = await saveConversationDurable(result);
      if (saveError != null) {
        _handleGenerationPersistenceFailure(
          generationId: generationId,
          error: saveError,
        );
        return;
      }
      state = state.copyWith(clearAutoRetryCount: true);
      completeActiveStreaming(result);
      _coordinator.finalize();
      _cleanupCoordinatorBridge(generationId);
      return;
    }
    // 重试信号：durable 落盘本次 attempt 的占位（空/异常/错误 assistant 消息）。
    final intermediateSaveError = await saveConversationDurable(
      state.activeConversation,
    );
    if (intermediateSaveError != null) {
      _handleGenerationPersistenceFailure(
        generationId: generationId,
        error: intermediateSaveError,
      );
      return;
    }
    if (!_coordinator.scheduleRetry()) {
      // 不再重试。autoRetry 开着却不再重试 = 达 maxRetryCount 上限（对应旧
      // 循环 autoRetryCount > maxRetryCount 分支），覆盖为上限文案；autoRetry
      // 关着 = 单次失败，保留 attempt 自身的错误文案不动。
      final policy = _coordinatorRetryPolicy;
      final reachedLimit = policy?.enabled ?? false;
      if (reachedLimit) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          errorMessage: '自动重试已达上限（${policy!.maxRetryCount} 次），请检查网络或调整重试设置',
        );
      } else {
        state = state.copyWith(clearAutoRetryCount: true);
      }
      completeActiveStreaming(null);
      _coordinator.finalize();
      _cleanupCoordinatorBridge(generationId);
    }
    // scheduleRetry 成功：等待窗口后新 attempt，不 complete completer。
  }

  /// 清理 coordinator 桥接字段。
  ///
  /// 同时清空旧 streaming session 字段（activeStreamingCompleter /
  /// latestStreamingReply / activeStreamingSubscription）：coordinator 路径下
  /// 它们与 _coordinator* 指向同一对象，统一清理避免残留串入下一轮 generation。
  ///
  /// [generationId] 为 null 时无条件清理（用于 pending save 失败：coordinator
  /// 尚未 start、_coordinatorGenerationId 仍为 null 的场景）；非 null 时仅当
  /// 仍是本次 generation 活跃才清理，避免 await 让出后被新 generation 覆盖。
  void _cleanupCoordinatorBridge(int? generationId) {
    if (generationId != null && _coordinatorGenerationId != generationId) {
      return;
    }
    clearActiveStreamingSession();
    _coordinatorCompleter = null;
    _coordinatorStreamingConversation = null;
    _coordinatorAssistantMessage = null;
    _coordinatorStreamingReply = null;
    _coordinatorResponseBuffer.clear();
    _coordinatorReasoningBuffer.clear();
    _coordinatorRetryPolicy = null;
    _coordinatorGenerationId = null;
  }

  /// generation 关键 checkpoint 的 durable save 失败处理。
  ///
  /// 标记 persistenceFailed 终态（[generationId] 为 null 表示失败发生在
  /// [_coordinator.start] 之前的 pending save，coordinator 尚未建立 handle，
  /// 跳过 [ChatGenerationCoordinator.markPersistenceFailure]），投影 inline error，
  /// complete completer(null)（不假成功），清理桥接字段。不重试、不重复请求。
  void _handleGenerationPersistenceFailure({
    required int? generationId,
    required Object error,
  }) {
    if (generationId != null) {
      _coordinator.markPersistenceFailure(error);
    }
    state = state.copyWith(
      isStreaming: false,
      isAutoRetryWaiting: false,
      clearAutoRetryCount: true,
      errorMessage: ChatErrorMessages.persistenceFailed,
      errorMessageAssistantId: _coordinatorAssistantMessage?.id,
      clearStreamingReply: true,
      clearEmptyReply: true,
      incrementHistoryRevision: true,
    );
    completeActiveStreaming(null);
    _cleanupCoordinatorBridge(generationId);
  }

  /// 编辑一条用户消息并从该节点重新生成后续回复。
  Future<void> editMessage({
    required String messageId,
    required String nextContent,
    List<UserMessageSegment> userMessageSegments = const [],
    String? templatePromptId,
    Map<String, String> templateVariableValues = const {},
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
      setErrorMessage(ChatErrorMessages.noModelConfigForRecalc);
      return;
    }

    final presetPrompt = resolvePresetPrompt(currentConversation);
    final branchUserMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.user,
      content: trimmedContent,
      createdAt: DateTime.now(),
      parentId: targetMessage.parentId,
      userMessageSegments: userMessageSegments,
      templatePromptId: templatePromptId,
      templateVariableValues: templateVariableValues,
    );
    final nextNodes = [...tree.nodes, branchUserMessage];
    final nextSelections = Map<String, String>.from(tree.selections);
    final branchParentId = targetMessage.effectiveParentId;
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
    await _sendWithOptionalAutoRetry(
      conversation: rebuiltConversation,
      modelConfig: modelConfig,
      presetPrompt: presetPrompt,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: branchUserMessage.id,
      reasoningEnabled: rebuiltConversation.reasoningEnabled,
      reasoningEffort: rebuiltConversation.reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpointTitle,
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
      setErrorMessage(ChatErrorMessages.retryOnlyLatest);
      return;
    }

    final modelConfig = resolveModelConfig(currentConversation);
    if (modelConfig == null) {
      setErrorMessage(ChatErrorMessages.noModelConfigForRetry);
      return;
    }

    final presetPrompt = resolvePresetPrompt(currentConversation);
    if (latestMessage.role == ChatMessageRole.user &&
        state.errorMessage != null) {
      final checkpointContext = resolveCheckpointContext(
        conversation: currentConversation,
        conversationMessages: activePath,
      );
      await _sendWithOptionalAutoRetry(
        conversation: currentConversation.copyWith(updatedAt: DateTime.now()),
        modelConfig: modelConfig,
        presetPrompt: presetPrompt,
        requestConversationMessages: checkpointContext.tailMessages,
        requestCheckpointChain: checkpointContext.checkpointChain,
        parentMessageId: latestMessage.id,
        reasoningEnabled: currentConversation.reasoningEnabled,
        reasoningEffort: currentConversation.reasoningEffort,
        appliedCheckpointTitle: checkpointContext.activeCheckpointTitle,
      );
      return;
    }

    final latestAssistantIndex = activePath.lastIndexWhere((message) {
      return message.role == ChatMessageRole.assistant;
    });
    if (latestAssistantIndex == -1 ||
        latestAssistantIndex != activePath.length - 1) {
      setErrorMessage(ChatErrorMessages.retryOnlyLatest);
      return;
    }

    final tree = resolveMessageTreeState(currentConversation);
    final latestAssistant = activePath[latestAssistantIndex];
    final parentId = latestAssistant.effectiveParentId;
    final requestMessages = activePath
        .take(latestAssistantIndex)
        .toList(growable: false);
    final errorAssistantId = state.errorMessageAssistantId;
    final isEmptyReplyNode =
        state.emptyReplyAssistantId != null &&
        state.emptyReplyAssistantId == latestAssistant.id;
    final isEmptyReply =
        latestAssistant.content.trim().isEmpty &&
        latestAssistant.reasoningContent.trim().isEmpty;
    final shouldRemoveNode =
        (errorAssistantId != null && errorAssistantId == latestAssistant.id) ||
        isEmptyReplyNode ||
        isEmptyReply;
    if (shouldRemoveNode) {
      final nextTree = removeNodeFromTree(
        treeState: tree,
        nodeId: latestAssistant.id,
      );
      final baseConversation = currentConversation.copyWith(
        messageNodes: nextTree.nodes,
        selectedChildByParentId: nextTree.selections,
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(
        conversations: replaceConversation(baseConversation),
        clearErrorMessage: true,
        clearEmptyReply: true,
      );
      saveConversation(baseConversation);

      final checkpointContext = resolveCheckpointContext(
        conversation: baseConversation,
        conversationMessages: requestMessages,
      );

      await _sendWithOptionalAutoRetry(
        conversation: baseConversation,
        modelConfig: modelConfig,
        presetPrompt: presetPrompt,
        requestConversationMessages: checkpointContext.tailMessages,
        requestCheckpointChain: checkpointContext.checkpointChain,
        parentMessageId: parentId == rootConversationParentId ? null : parentId,
        reasoningEnabled: baseConversation.reasoningEnabled,
        reasoningEffort: baseConversation.reasoningEffort,
        appliedCheckpointTitle: checkpointContext.activeCheckpointTitle,
      );
      return;
    }
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
      clearEmptyReply: true,
    );
    saveConversation(baseConversation);

    final checkpointContext = resolveCheckpointContext(
      conversation: baseConversation,
      conversationMessages: requestMessages,
    );

    await _sendWithOptionalAutoRetry(
      conversation: baseConversation,
      modelConfig: modelConfig,
      presetPrompt: presetPrompt,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: parentId == rootConversationParentId ? null : parentId,
      reasoningEnabled: baseConversation.reasoningEnabled,
      reasoningEffort: baseConversation.reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpointTitle,
    );
  }

  /// 发送新消息并触发模型流式回复。
  Future<void> sendMessage({
    required String content,
    required LlmModelConfig modelConfig,
    required PresetPrompt? presetPrompt,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    List<UserMessageSegment> userMessageSegments = const [],
    String? templatePromptId,
    Map<String, String> templateVariableValues = const {},
    Duration? retryDelay,
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
      templatePromptId: templatePromptId,
      templateVariableValues: templateVariableValues,
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
    await _sendWithOptionalAutoRetry(
      conversation: pendingConversation,
      modelConfig: modelConfig,
      presetPrompt: presetPrompt,
      requestConversationMessages: checkpointContext.tailMessages,
      requestCheckpointChain: checkpointContext.checkpointChain,
      parentMessageId: userMessage.id,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      appliedCheckpointTitle: checkpointContext.activeCheckpointTitle,
      retryDelay: retryDelay,
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

    final parentId = targetMessage.effectiveParentId;
    final siblingIds = tree.nodes
        .where((message) {
          return message.effectiveParentId == parentId;
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
          return message.effectiveParentId == parentId;
        })
        .toList(growable: false);
    final deletedIndex = siblingIds.indexOf(messageId);
    final nextSelections = Map<String, String>.from(nextTree.selections);
    if (remainingSiblings.isEmpty) {
      nextSelections.remove(parentId);
    } else if (deletedIndex > 0) {
      final prevId = siblingIds[deletedIndex - 1];
      final prevRemaining = remainingSiblings
          .where((m) => m.id == prevId)
          .firstOrNull;
      nextSelections[parentId] =
          prevRemaining?.id ?? remainingSiblings.first.id;
    } else {
      nextSelections[parentId] = remainingSiblings.first.id;
    }

    updateActiveConversation(
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

  List<String> _resolveAncestorPath(
    List<ChatMessage> nodes, {
    required String targetId,
  }) {
    final nodeById = <String, ChatMessage>{
      for (final node in nodes) node.id: node,
    };

    if (!nodeById.containsKey(targetId)) return const [];

    final path = <String>[];
    var currentId = targetId;
    while (true) {
      final node = nodeById[currentId];
      if (node == null) break;
      path.add(currentId);
      final parentId = node.effectiveParentId;
      if (parentId == rootConversationParentId) break;
      currentId = parentId;
    }

    return path.reversed.toList(growable: false);
  }
}
