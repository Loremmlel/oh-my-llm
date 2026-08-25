import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/features/settings/application/preferences/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../generation/chat_generation_contract.dart';
import '../generation/chat_generation_coordinator.dart';
import '../generation/chat_generation_lifecycle.dart';
import '../requests/chat_request_message_builder.dart';
import 'chat_sessions_controller_streaming.dart';
import 'chat_sessions_controller_support.dart';
import '../requests/checkpoint_request_context.dart';
import 'chat_message_tree.dart';
import 'chat_sessions_state.dart';
import '../../domain/models/chat_checkpoint.dart';
import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_conversation_summary.dart';
import '../../domain/chat_error_messages.dart';
import '../../domain/chat_message_parent.dart';
import '../../domain/models/chat_message.dart';
import '../ports/chat_generation_client.dart';
import '../ports/chat_conversation_repository.dart';

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

/// 是否正在进行流式请求（由 [ChatSessionsState.isStreaming] 派生，仅在流开始/
/// 结束时重建）。
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
    chatSessionsProvider.select((state) {
      // generation phase（如 finalizing 的 durable save 窗口）保持 busy，阻止
      // UI 在终态落盘期间发送新 generation 覆盖 run 字段；派生布尔
      // （isStreaming/isAutoRetryWaiting）已被 phase.isBusy 涵盖，无需重复。
      return (state.generation?.phase.isBusy ?? false) || state.isCheckpointing;
    }),
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
    implements ChatGenerationHost {
  @override
  ChatConversationRepository get repository =>
      ref.read(chatConversationRepositoryProvider);

  ChatGenerationClient get chatClient => ref.read(chatGenerationClientProvider);

  // ── ChatGenerationCoordinator 桥接 ────────────────────────────────────────

  ChatGenerationCoordinator? _generationCoordinator;

  /// 懒初始化协调器：首次发送时才读取 chatClient，避免 build() 阶段触发
  /// chatGenerationClientProvider（连带 appNetworkLogger）在未发送消息的
  /// 场景（如 widget bootstrap）下产生副作用。
  ChatGenerationCoordinator get _coordinator {
    _generationCoordinator ??= ChatGenerationCoordinator(client: chatClient);
    return _generationCoordinator!;
  }

  /// controller 是否已 dispose。host 方法 await 后据此跳过 state 写入。
  bool _disposed = false;

  /// 是否占用（阻止新 generation / 会话切换 / 冲突 CRUD）。
  ///
  /// 从 [ChatSessionsState.generation] 的 phase 单向派生，使 attempt 终态后的
  /// durable save 窗口（`finalizing`）仍保持 busy，阻止新 generation 覆盖 run
  /// 字段（不变量 5）。无 generation snapshot 时仅检查点占用生效。
  bool get _isBusy {
    if (_generationCoordinator?.hasActive ?? false) {
      return true;
    }
    return (state.generation?.phase.isBusy ?? false) || state.isCheckpointing;
  }

  /// 将 [ChatGenerationProgress] 投影到 state：写入 canonical snapshot 与流式
  /// 增量，并在流式开始时清除错误/空回复标记、在 persistenceFailed 时补齐错误
  /// 文案。派生布尔（isStreaming/isAutoRetryWaiting/autoRetryCount）由
  /// [ChatSessionsState] 从 phase 单向派生，controller 不再单独维护（不变量：
  /// 生命周期状态唯一事实来源）。run 在调 host 前预投影 finalizing/stopping。
  void _projectProgress(ChatGenerationProgress progress) {
    final snapshot = progress.snapshot;
    assert(checkGenerationInvariants(snapshot));
    final phase = snapshot.phase;
    // preparing 也计为「流式形态」：清除上一次的错误与空回复标记，保持停止
    // 按钮可用（ComposerSendButton 的 isStopping 依据派生的 isStreaming）。
    final isStreamingLike =
        phase == ChatGenerationPhase.preparing ||
        phase == ChatGenerationPhase.streaming;
    // persistenceFailed 是终态，但 run 的 _terminal 只投影 phase；错误文字在此
    // 统一补齐，使 save 失败对用户显式可见。
    final isPersistenceFailed = phase == ChatGenerationPhase.persistenceFailed;
    state = state.copyWith(
      generation: snapshot,
      streamingReply: progress.streamingReply,
      clearStreamingReply: progress.streamingReply == null,
      errorMessage: isPersistenceFailed
          ? ChatErrorMessages.persistenceFailed
          : null,
      clearErrorMessage: isStreamingLike,
      clearEmptyReply: isStreamingLike,
    );
  }

  // ── 生命周期 ────────────────────────────────────────────────────────────────

  /// 读取持久化数据并初始化当前会话状态。
  ///
  /// 若数据库为空则自动创建一个新的空白会话作为初始状态。
  @override
  ChatSessionsState build() {
    ref.onDispose(() {
      _disposed = true;
      // dispose 当前 run：cancel 订阅/定时器，complete(null)，使公开 Future
      // 不挂起；之后迟到回调被 run 的 _disposed/_outcome guard 丢弃。
      _generationCoordinator?.dispose();
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
      throw const ChatGenerationException(ChatErrorMessages.busy);
    }

    final currentConversation = state.activeConversation;
    final presetPrompt = resolvePresetPrompt(currentConversation);
    final sourceContext = resolveCheckpointRequestContext(
      checkpoints: currentConversation.checkpoints,
      selectedCheckpointId: sourceCheckpointId,
      conversationMessages: currentConversation.messages,
    );
    if (sourceCheckpointId != null && sourceContext.checkpointChain.isEmpty) {
      throw const ChatGenerationException(
        ChatErrorMessages.incompatibleCheckpoint,
      );
    }

    final summaryMessages = sourceCheckpointId == null
        ? currentConversation.messages
        : sourceContext.tailMessages;
    if (summaryMessages.isEmpty) {
      throw const ChatGenerationException(
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
        ChatGenerationRequest(
          target: _targetFromModelConfig(modelConfig),
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
        ),
      );
      final checkpointContent = result.content.trim();
      if (checkpointContent.isEmpty) {
        throw const ChatGenerationException('模型没有返回可用的检查点内容。');
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

  ChatGenerationRequestTarget _targetFromModelConfig(
    LlmModelConfig modelConfig,
  ) {
    return ChatGenerationRequestTarget(
      protocol: modelConfig.apiProtocol,
      endpoint: modelConfig.apiUrl.trim(),
      apiKey: modelConfig.apiKey,
      model: modelConfig.modelName,
    );
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

  /// 构造 [ChatGenerationCommand] 并交给 coordinator 启动一次 generation。
  /// retry 策略从 settings 一次性快照，等待窗口期内用户改动不影响当前 generation。
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
    final retryPolicy = ChatRetryPolicy.fromSnapshot(
      conversationAutoRetryEnabled: conversation.autoRetryEnabled,
      settings: ref.read(autoRetrySettingsProvider),
    );
    final command = ChatGenerationCommand(
      conversation: conversation,
      modelConfig: modelConfig,
      presetPrompt: presetPrompt,
      requestConversationMessages: requestConversationMessages,
      requestCheckpointChain: requestCheckpointChain,
      parentMessageId: parentMessageId,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      appliedCheckpointTitle: appliedCheckpointTitle,
      retryPolicy: retryPolicy,
      retryDelay: retryDelay,
    );
    await _coordinator.start(command, this);
  }

  /// 停止当前 generation（facade）。
  ///
  /// 无 run 返回当前会话；有 run 记录停止意图并返回同一 completion（幂等）。
  /// preparing/streaming/retryWaiting/finalizing 各阶段的 durable save 与终态
  /// 投影均由 run 的串行路径 + host.stop 统一处理，controller 不再猜阶段。
  Future<ChatConversation?> stopStreaming() async {
    final completion = _coordinator.currentCompletion;
    if (completion == null) {
      // 无 active run：无 snapshot 时派生布尔（isStreaming/isAutoRetryWaiting/
      // autoRetryCount）本就为 false/0，此处仅清除遗留错误标记。
      state = state.copyWith(clearErrorMessage: true);
      return state.activeConversation;
    }
    _coordinator.stop();
    return (await completion) ?? state.activeConversation;
  }

  // ── ChatGenerationHost ───────────────────────────────────────────────────

  @override
  Future<ChatPrepareResult> prepare(ChatGenerationCommand command) async {
    // 创建占位 assistant、追加到树、写 state（conversation/streamingReply 业务
    // 字段）、durable pending checkpoint。错误清除由 run 的 preparing 投影统一
    // 提供，此处不写。失败返回 ChatPrepareFailure，run 据此中止、不启动网络。
    final timestamp = DateTime.now();
    final tree = resolveMessageTreeState(command.conversation);
    final assistantParentId =
        command.parentMessageId ?? rootConversationParentId;
    final assistantMessage = ChatMessage(
      id: generateEntityId(),
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: timestamp.add(const Duration(milliseconds: 1)),
      parentId: assistantParentId,
      isStreaming: true,
      assistantModelDisplayName: command.modelConfig.displayName,
      appliedCheckpointTitle: command.appliedCheckpointTitle,
    );
    final initialTree = appendNodeToTree(
      treeState: tree,
      node: assistantMessage,
      parentId: assistantParentId,
    );
    final streamingConversation = command.conversation.copyWith(
      messageNodes: initialTree.nodes,
      selectedChildByParentId: initialTree.selections,
      updatedAt: timestamp,
      reasoningEnabled: command.reasoningEnabled,
      reasoningEffort: command.reasoningEffort,
    );
    final streamingReply = ChatStreamingReply(
      conversationId: streamingConversation.id,
      assistantMessageId: assistantMessage.id,
    );
    state = state.copyWith(
      conversations: replaceConversation(streamingConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(streamingConversation),
      ),
      streamingReply: streamingReply,
      incrementHistoryRevision: true,
    );
    final pendingError = await saveConversationDurable(streamingConversation);
    if (_disposed) {
      return ChatPrepareFailure(StateError('disposed'));
    }
    if (pendingError != null) {
      return ChatPrepareFailure(pendingError);
    }
    final request = ChatGenerationRequest(
      target: _targetFromModelConfig(command.modelConfig),
      messages: buildRequestMessages(
        presetPrompt: command.presetPrompt,
        conversationMessages: command.requestConversationMessages,
        checkpointChain: command.requestCheckpointChain,
        filter: ExcludeByIdMessageFilter(
          command.conversation.excludedMessageIds.toSet(),
        ),
      ),
      reasoningEffort:
          command.reasoningEnabled && command.modelConfig.supportsReasoning
          ? command.reasoningEffort
          : null,
      streamIdleTimeout:
          command.retryPolicy.retryOnTimeout && command.retryPolicy.enabled
          ? command.retryPolicy.timeout
          : null,
    );
    return ChatPrepareSuccess(
      request: request,
      streamingConversation: streamingConversation,
      assistantMessage: assistantMessage,
      streamingReply: streamingReply,
    );
  }

  @override
  Future<ChatAttemptDecision> completeAttempt(
    ChatAttemptSnapshot attempt,
  ) async {
    final streamingConversation = attempt.streamingConversation;
    final assistantMessage = attempt.assistantMessage;
    final streamingReply = attempt.streamingReply;
    final retryPolicy = attempt.retryPolicy;
    final FinishGenerationResult result;
    switch (attempt.attemptOutcome) {
      case ChatGenerationSuccess(
        :final content,
        :final reasoningContent,
        :final finishReason,
      ):
        final updated = streamingReply.copyWith(
          content: content,
          reasoningContent: reasoningContent,
          finishReason: finishReason,
        );
        replaceStreamingReplyInMemory(updated);
        result = await finishGenerationSuccess(
          streamingConversation: streamingConversation,
          assistantMessage: assistantMessage,
          streamingReply: updated,
          autoRetryEnabled: retryPolicy.enabled,
          retryOnAbnormalFinishReason: retryPolicy.retryOnAbnormalFinishReason,
          skipEmptyCheck: true,
        );
      case ChatGenerationEmptyReply(:final finishReason):
        final updated = streamingReply.copyWith(finishReason: finishReason);
        replaceStreamingReplyInMemory(updated);
        result = await finishGenerationSuccess(
          streamingConversation: streamingConversation,
          assistantMessage: assistantMessage,
          streamingReply: updated,
          autoRetryEnabled: retryPolicy.enabled,
          retryOnAbnormalFinishReason: retryPolicy.retryOnAbnormalFinishReason,
        );
      case ChatGenerationFailure(:final error, :final stackTrace):
        await finishGenerationError(
          streamingConversation: streamingConversation,
          streamingReply: streamingReply,
          assistantMessage: assistantMessage,
          error: error,
          stackTrace: stackTrace ?? StackTrace.empty,
        );
        result = const FinishRetry();
      case ChatGenerationCancelled():
      case ChatGenerationPersistenceFailure():
        // 不可达：attemptOutcome 只会是 success/empty/failure。
        result = const FinishRetry();
    }
    if (_disposed) {
      return ChatAttemptPersistenceFailed(StateError('disposed'));
    }
    switch (result) {
      case FinishSuccess(:final conversation):
        final error = await saveConversationDurable(conversation);
        if (_disposed) {
          return ChatAttemptPersistenceFailed(StateError('disposed'));
        }
        if (error != null) {
          return ChatAttemptPersistenceFailed(error);
        }
        return ChatAttemptSucceed(conversation);
      case FinishOutputRuleError(:final conversation):
        final error = await saveConversationDurable(conversation);
        if (_disposed) {
          return ChatAttemptPersistenceFailed(StateError('disposed'));
        }
        if (error != null) {
          return ChatAttemptPersistenceFailed(error);
        }
        return ChatAttemptOutputRuleFailed(
          conversation,
          ChatGenerationFailure(
            generationId: attempt.generationId,
            attempt: attempt.attempt,
            error: ChatErrorMessages.outputRuleEmptied,
          ),
        );
      case FinishRetry():
        final intermediateError = await saveConversationDurable(
          state.activeConversation,
        );
        if (_disposed) {
          return ChatAttemptPersistenceFailed(StateError('disposed'));
        }
        if (intermediateError != null) {
          return ChatAttemptPersistenceFailed(intermediateError);
        }
        if (_canRetry(retryPolicy, attempt.attempt)) {
          return const ChatAttemptRetry();
        }
        final terminalOutcome = _retryExhaustedOutcome(attempt);
        final reachedLimit = retryPolicy.enabled;
        // 终态保留错误：reachedLimit（启用但达上限）设上限消息；否则保留
        // finishGenerationError 已投影的原始错误。clearErrorMessage=false 避免误清
        // 刚写入的错误（retry 禁用时清掉 finishGenerationError 的错误是 sendMessage
        // 错误显示丢失的根因）。autoRetryCount 由终端 phase 派生归零，此处不写。
        if (reachedLimit) {
          state = state.copyWith(
            errorMessage:
                '自动重试已达上限（${retryPolicy.maxRetryCount} 次），请检查网络或调整重试设置',
            clearErrorMessage: false,
          );
        }
        return ChatAttemptGiveUp(terminalOutcome);
    }
  }

  @override
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial) async {
    final streamingReply =
        partial.streamingReply?.copyWith(
          content: partial.content,
          reasoningContent: partial.reasoning,
        ) ??
        ChatStreamingReply(
          conversationId: partial.streamingConversation.id,
          assistantMessageId: partial.assistantMessage.id,
        );
    final stoppedConversation = buildConversationAfterStreamingInterrupt(
      conversation: state.activeConversation,
      streamingReply: streamingReply,
    );
    final assistantMessageId = streamingReply.assistantMessageId;
    final isEmpty =
        partial.content.trim().isEmpty && partial.reasoning.trim().isEmpty;
    final shouldMarkEmptyReply = isEmpty;
    // 派生布尔（isStreaming/isAutoRetryWaiting/autoRetryCount）由 stopping phase
    // 单向派生归位，此处只写终态业务字段（conversation/错误/空回复标记）与清流式
    // reply（停止后不再流式渲染）。
    state = state.copyWith(
      conversations: replaceConversation(stoppedConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(stoppedConversation),
      ),
      clearStreamingReply: true,
      incrementHistoryRevision: true,
      emptyReplyAssistantId: shouldMarkEmptyReply ? assistantMessageId : null,
      errorMessage: shouldMarkEmptyReply
          ? ChatErrorMessages.stoppedByUser
          : null,
      errorMessageAssistantId: shouldMarkEmptyReply ? assistantMessageId : null,
      clearErrorMessage: !shouldMarkEmptyReply,
      clearEmptyReply: !shouldMarkEmptyReply,
    );
    final error = await saveConversationDurable(stoppedConversation);
    if (_disposed) {
      return ChatStopPersistenceFailed(StateError('disposed'));
    }
    if (error != null) {
      return ChatStopPersistenceFailed(error);
    }
    return ChatStopCancelled(stoppedConversation);
  }

  @override
  void projectProgress(ChatGenerationProgress progress) {
    _projectProgress(progress);
  }

  /// 是否还能再重试一次（移植自旧 _GenerationHandle.scheduleRetry 的上限判定）。
  bool _canRetry(ChatRetryPolicy policy, int attempt) {
    if (!policy.enabled) return false;
    if (policy.maxRetryCount > 0 && attempt >= policy.maxRetryCount) {
      return false;
    }
    return true;
  }

  /// retry 耗尽时的终态 outcome：异常 finish（Success）转 Failure，其余原样保留
  /// （移植自旧 _retryExhaustedOutcome）。
  ChatGenerationOutcome _retryExhaustedOutcome(ChatAttemptSnapshot attempt) {
    final outcome = attempt.attemptOutcome;
    if (outcome is ChatGenerationSuccess) {
      return ChatGenerationFailure(
        generationId: outcome.generationId,
        attempt: outcome.attempt,
        error: '模型返回异常停止原因（finish_reason: ${outcome.finishReason}），自动重试已达上限',
      );
    }
    return outcome;
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
