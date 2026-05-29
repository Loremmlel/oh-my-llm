import 'dart:async';
import 'dart:math';

import '../../../core/utils/id_generator.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/preset_prompt.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import 'chat_message_tree.dart';
import 'chat_request_message_builder.dart';
import 'chat_sessions_controller_support.dart';
import 'chat_sessions_state.dart';

/// 为 [ChatSessionsController] 提供流式回复生命周期管理。
mixin ChatSessionsControllerStreaming on ChatSessionsControllerSupport {
  static const streamUiFlushInterval = Duration(milliseconds: 300);

  ChatCompletionClient get chatClient;
  StreamSubscription<ChatCompletionChunk>? get activeStreamingSubscription;
  set activeStreamingSubscription(
    StreamSubscription<ChatCompletionChunk>? value,
  );

  Completer<ChatConversation?>? get activeStreamingCompleter;
  set activeStreamingCompleter(Completer<ChatConversation?>? value);

  ChatStreamingReply? get latestStreamingReply;
  set latestStreamingReply(ChatStreamingReply? value);

  bool get streamStopRequested;
  set streamStopRequested(bool value);

  bool get autoRetryCancelled;
  set autoRetryCancelled(bool value);

  /// 终止当前流式回复，并保留已收到的部分内容。
  ///
  /// 通过取消 [StreamSubscription] 实现：取消信号向下传播至 `async*` 生成器，
  /// 中断对 SSE `ByteStream` 的监听，最终由 `dart:io` 的 `IOClient` 关闭底层
  /// TCP socket。服务器检测到连接断开后会停止生成 token。
  ///
  /// OpenAI 兼容接口没有显式的"停止生成"API 端点，关闭 TCP 连接是唯一的
  /// 标准方式。主流 LLM 服务（OpenAI、DeepSeek、Google 等）均支持此机制。
  Future<ChatConversation?> stopStreaming() async {
    if (state.isAutoRetryWaiting) {
      autoRetryCancelled = true;
      state = state.copyWith(
        isAutoRetryWaiting: false,
        clearAutoRetryCount: true,
        clearErrorMessage: true,
      );
      return null;
    }

    if (!state.isStreaming) {
      return null;
    }

    streamStopRequested = true;
    final subscription = activeStreamingSubscription;
    activeStreamingSubscription = null;
    await subscription?.cancel();

    final stoppedConversation = buildConversationAfterStreamingInterrupt(
      conversation: state.activeConversation,
      streamingReply: latestStreamingReply ?? state.streamingReply,
    );
    state = state.copyWith(
      conversations: replaceConversation(stoppedConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(stoppedConversation),
      ),
      isStreaming: false,
      clearStreamingReply: true,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    saveAllConversations();

    completeActiveStreaming(stoppedConversation);
    clearActiveStreamingSession();
    return stoppedConversation;
  }

  /// 在流式请求失败时，保留已生成内容或清除空白占位节点。
  Future<void> handleStreamingFailure({
    required ChatConversation conversation,
    required ChatStreamingReply streamingReply,
    required String assistantMessageId,
    required String errorMessage,
  }) async {
    final tree = resolveMessageTreeState(conversation);
    final isEmpty = streamingReply.content.trim().isEmpty &&
        streamingReply.reasoningContent.trim().isEmpty;
    final nextTree = isEmpty
        ? replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: assistantMessageId,
            nextContent: '',
            nextReasoningContent: '',
            isStreaming: false,
          )
        : replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: assistantMessageId,
            nextContent: streamingReply.content,
            nextReasoningContent: streamingReply.reasoningContent,
            isStreaming: false,
          );

    final nextConversation = conversation.copyWith(
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      conversations: replaceConversation(nextConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(nextConversation),
      ),
      isStreaming: false,
      errorMessage: errorMessage,
      errorMessageAssistantId: assistantMessageId,
      clearStreamingReply: true,
      incrementHistoryRevision: true,
    );
    saveAllConversations();
  }

  /// 把 assistant 回复以流式方式写回当前会话。
  Future<ChatConversation?> streamAssistantReply({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PresetPrompt? presetPrompt,
    required List<ChatMessage> requestConversationMessages,
    List<ChatCheckpoint> requestCheckpointChain = const [],
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    String appliedCheckpointTitle = '',
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
    var streamingReply = ChatStreamingReply(
      conversationId: streamingConversation.id,
      assistantMessageId: assistantMessage.id,
    );
    final completer = Completer<ChatConversation?>();
    activeStreamingCompleter = completer;
    latestStreamingReply = streamingReply;

    state = state.copyWith(
      conversations: replaceConversation(streamingConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(streamingConversation),
      ),
      isStreaming: true,
      streamingReply: streamingReply,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    saveAllConversations();
    if (completer.isCompleted ||
        activeStreamingCompleter != completer ||
        !state.isStreaming) {
      return completer.future;
    }
    streamStopRequested = false;

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    var lastUiFlushAt = timestamp.subtract(streamUiFlushInterval);

    Future<void> completeWithSuccess() async {
      if (streamStopRequested || completer.isCompleted) {
        return;
      }

      streamingReply = streamingReply.copyWith(
        content: responseBuffer.toString(),
        reasoningContent: reasoningBuffer.toString(),
      );
      latestStreamingReply = streamingReply;
      replaceStreamingReplyInMemory(streamingReply);

      // 空回复：移除空白占位节点，走失败路径触发重试
      if (_isEmptyStreamingReply(streamingReply: streamingReply)) {
        final tree = resolveMessageTreeState(streamingConversation);
        final nextTree = replaceAssistantMessageInTree(
          treeState: tree,
          assistantMessageId: assistantMessage.id,
          nextContent: '',
          nextReasoningContent: '',
          isStreaming: false,
        );
        final cleanedConversation = streamingConversation.copyWith(
          messageNodes: nextTree.nodes,
          selectedChildByParentId: nextTree.selections,
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(
          conversations: replaceConversation(cleanedConversation),
          conversationSummaries: replaceOrAddSummary(
            state.conversationSummaries,
            summaryFromConversation(cleanedConversation),
          ),
          isStreaming: false,
          errorMessage: '模型返回了空回复',
          errorMessageAssistantId: assistantMessage.id,
          clearStreamingReply: true,
          incrementHistoryRevision: true,
        );
        saveAllConversations();
        completeActiveStreaming(null);
        clearActiveStreamingSession();
        return;
      }

      final completedConversation = applyStreamingReplyToConversation(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        isStreaming: false,
      ).copyWith(updatedAt: DateTime.now());

      state = state.copyWith(
        conversations: replaceConversation(completedConversation),
        conversationSummaries: replaceOrAddSummary(
          state.conversationSummaries,
          summaryFromConversation(completedConversation),
        ),
        isStreaming: false,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      saveAllConversations();
      completeActiveStreaming(completedConversation);
      clearActiveStreamingSession();
    }

    Future<void> completeWithError(Object error, StackTrace stackTrace) async {
      if (streamStopRequested || completer.isCompleted) {
        return;
      }

      final errorMessage = error is ChatCompletionException
          ? error.message
          : formatUnexpectedStreamingError(error, stackTrace);
      await handleStreamingFailure(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        assistantMessageId: assistantMessage.id,
        errorMessage: errorMessage,
      );
      completeActiveStreaming(null);
      clearActiveStreamingSession();
    }

    activeStreamingSubscription = chatClient
        .streamCompletion(
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
        )
        .listen(
          (chunk) {
            if (chunk.isEmpty || streamStopRequested) {
              return;
            }

            responseBuffer.write(chunk.contentDelta);
            reasoningBuffer.write(chunk.reasoningDelta);
            streamingReply = streamingReply.copyWith(
              content: responseBuffer.toString(),
              reasoningContent: reasoningBuffer.toString(),
            );
            latestStreamingReply = streamingReply;
            final now = DateTime.now();
            if (now.difference(lastUiFlushAt) < streamUiFlushInterval) {
              return;
            }

            replaceStreamingReplyInMemory(streamingReply);
            lastUiFlushAt = now;
          },
          onDone: () {
            unawaited(completeWithSuccess());
          },
          onError: (Object error, StackTrace stackTrace) {
            unawaited(completeWithError(error, stackTrace));
          },
          cancelOnError: false,
        );

    return completer.future;
  }

  /// 仅刷新流式增量，不去改动完整会话列表。
  void replaceStreamingReplyInMemory(ChatStreamingReply streamingReply) {
    if (state.streamingReply == streamingReply) {
      return;
    }

    state = state.copyWith(streamingReply: streamingReply);
  }

  ChatConversation buildConversationAfterStreamingInterrupt({
    required ChatConversation conversation,
    required ChatStreamingReply? streamingReply,
  }) {
    if (streamingReply == null) {
      return conversation.copyWith(updatedAt: DateTime.now());
    }

    final hasPartialContent =
        !_isEmptyStreamingReply(streamingReply: streamingReply);
    final tree = resolveMessageTreeState(conversation);
    final nextTree = hasPartialContent
        ? replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: streamingReply.assistantMessageId,
            nextContent: streamingReply.content,
            nextReasoningContent: streamingReply.reasoningContent,
            isStreaming: false,
          )
        : removeNodeFromTree(
            treeState: tree,
            nodeId: streamingReply.assistantMessageId,
          );

    return conversation.copyWith(
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
      updatedAt: DateTime.now(),
    );
  }

  /// 检查流式回复是否为空（无正文内容且无推理内容）。
  static bool _isEmptyStreamingReply({
    required ChatStreamingReply streamingReply,
  }) {
    return streamingReply.content.trim().isEmpty &&
        streamingReply.reasoningContent.trim().isEmpty;
  }

  void completeActiveStreaming(ChatConversation? conversation) {
    final completer = activeStreamingCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    completer.complete(conversation);
  }

  void clearActiveStreamingSession() {
    activeStreamingSubscription = null;
    activeStreamingCompleter = null;
    latestStreamingReply = null;
    streamStopRequested = false;
  }

  /// 在自动重试模式下发送消息：出错时自动等待下分钟的 0-15 秒窗口后重试，
  /// 直到成功或用户手动终止。
  Future<void> sendMessageWithAutoRetry({
    required ChatConversation pendingConversation,
    required LlmModelConfig modelConfig,
    required PresetPrompt? presetPrompt,
    required List<ChatMessage> requestConversationMessages,
    required List<ChatCheckpoint> requestCheckpointChain,
    required String? parentMessageId,
    required bool reasoningEnabled,
    required ReasoningEffort reasoningEffort,
    required String appliedCheckpointTitle,
    Duration? retryDelay,
    int maxRetryCount = 0,
    int maxJitterMs = 15000,
  }) async {
    autoRetryCancelled = false;
    state = state.copyWith(
      conversations: replaceConversation(pendingConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(pendingConversation),
      ),
      clearErrorMessage: true,
      clearAutoRetryCount: true,
      incrementHistoryRevision: true,
    );
    saveAllConversations();

    var isFirstAttempt = true;
    while (true) {
      if (autoRetryCancelled) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          clearErrorMessage: true,
        );
        return;
      }

      await _waitForRetryWindow(
        isFirstAttempt: isFirstAttempt,
        overrideDelay: retryDelay,
        maxJitterMs: maxJitterMs,
      );
      isFirstAttempt = false;

      if (autoRetryCancelled) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          clearErrorMessage: true,
        );
        return;
      }

      state = state.copyWith(
        conversations: replaceConversation(pendingConversation),
        conversationSummaries: replaceOrAddSummary(
          state.conversationSummaries,
          summaryFromConversation(pendingConversation),
        ),
        isAutoRetryWaiting: false,
        autoRetryCount: state.autoRetryCount + 1,
        clearErrorMessage: true,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      saveAllConversations();

      if (maxRetryCount > 0 &&
          state.autoRetryCount > maxRetryCount) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          errorMessage: '自动重试已达上限（$maxRetryCount 次），请检查网络或调整重试设置',
        );
        return;
      }

      final result = await streamAssistantReply(
        conversation: pendingConversation,
        modelConfig: modelConfig,
        presetPrompt: presetPrompt,
        requestConversationMessages: requestConversationMessages,
        requestCheckpointChain: requestCheckpointChain,
        parentMessageId: parentMessageId,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: reasoningEffort,
        appliedCheckpointTitle: appliedCheckpointTitle,
      );

      if (result != null) {
        state = state.copyWith(clearAutoRetryCount: true);
        return;
      }

      if (autoRetryCancelled) {
        state = state.copyWith(clearAutoRetryCount: true);
        return;
      }

      // 仍旧检查 auto-retry 是否还开着（可能在流式期间被用户关闭）
      final currentConversation = state.activeConversation;
      if (!currentConversation.autoRetryEnabled) {
        state = state.copyWith(clearAutoRetryCount: true);
        return;
      }
    }
  }

  /// 等待到下一个发送窗口（每分钟 0-15 秒之间的随机毫秒）。
  Future<void> _waitForRetryWindow({
    required bool isFirstAttempt,
    Duration? overrideDelay,
    int maxJitterMs = 15000,
  }) async {
    if (overrideDelay != null) {
      state = state.copyWith(isAutoRetryWaiting: true);
      await Future.delayed(overrideDelay);
      return;
    }

    final now = DateTime.now();
    final currentSecond = now.second;

    if (isFirstAttempt) {
      return;
    } else {
      final msToNextMinute = (60 - currentSecond) * 1000 - now.millisecond;
      final jitterMs = maxJitterMs > 0 ? Random().nextInt(maxJitterMs) : 0;
      state = state.copyWith(isAutoRetryWaiting: true);
      await Future.delayed(Duration(milliseconds: msToNextMinute + jitterMs));
    }
  }

  /// 保留原始异常并附加堆栈，方便开发者直接定位问题。
  String formatUnexpectedStreamingError(Object error, StackTrace stackTrace) {
    final rawError = error.toString();
    final normalizedError = rawError.trim();
    final header = normalizedError.isEmpty
        ? '请求未完成，请检查网络、API URL 或模型配置。'
        : normalizedError;
    return '$header\n\n```text\n$stackTrace\n```';
  }
}
