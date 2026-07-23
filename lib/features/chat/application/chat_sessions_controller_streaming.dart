import 'dart:async';
import 'dart:math';

import '../../../core/utils/id_generator.dart';
import '../../settings/application/output_processing_settings_controller.dart';
import '../../settings/domain/models/auto_retry_settings.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/preset_prompt.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_checkpoint.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/chat_error_messages.dart';
import '../domain/models/chat_message.dart';
import 'chat_message_tree.dart';
import 'chat_request_message_builder.dart';
import 'chat_sessions_controller_support.dart';
import 'chat_sessions_state.dart';
import 'output_regex_processor.dart';

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

  int get requestGeneration;
  set requestGeneration(int value);

  /// 终止当前流式回复，并保留已收到的部分内容。
  ///
  /// 通过取消 [StreamSubscription] 实现：取消信号向下传播至 `async*` 生成器，
  /// 中断对 SSE `ByteStream` 的监听，最终由 `dart:io` 的 `IOClient` 关闭底层
  /// TCP socket。服务器检测到连接断开后会停止生成 token。
  ///
  /// OpenAI 兼容接口没有显式的"停止生成"API 端点，关闭 TCP 连接是唯一的
  /// 标准方式。主流 LLM 服务（OpenAI、DeepSeek、Google 等）均支持此机制。
  ///
  /// 统一处理三种终止场景：自动重试等待中、流式间隙、流式进行中。
  /// 无论哪种场景，都会取消可能存在的 subscription 并 complete 对应 completer，
  /// 避免 [sendMessageWithAutoRetry] 的 await 永久挂起，从而一次点击即可终止。
  Future<ChatConversation?> stopStreaming() async {
    autoRetryCancelled = true;
    streamStopRequested = true;

    // 取消可能存在的流式订阅（流式进行中才有值；间隙/等待态下为 null）。
    // 不 await cancel：token 空闲间隙时 socket 无数据流动，cancel() 返回的 Future
    // 可能迟迟不完成，会阻塞后续 UI 状态重置，导致按钮停留在「终止」态、需点两次。
    // streamStopRequested 已置 true，配合 onData/完成回调守卫可安全地让 socket 后台关闭。
    final subscription = activeStreamingSubscription;
    activeStreamingSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }

    // complete completer，避免 streamAssistantReply 的 future 永久挂起。
    final streamingReply = latestStreamingReply ?? state.streamingReply;
    final wasStreaming = state.isStreaming;

    // 非流式且无回复（自动重试等待中点停止）时无需重建 conversation 或落盘：
    // 重建只会 copyWith(updatedAt) 干扰按更新时间排序的历史列表。
    final shouldSave = wasStreaming || streamingReply != null;
    final stoppedConversation = shouldSave
        ? buildConversationAfterStreamingInterrupt(
            conversation: state.activeConversation,
            streamingReply: streamingReply,
          )
        : state.activeConversation;

    final assistantMessageId = streamingReply?.assistantMessageId;

    // 未收到任何模型内容时，保留空占位节点并标记空回复，便于用户重试；
    // 收到部分内容则保留已生成内容。
    final isEmpty = streamingReply == null ||
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
      // 未收到内容时标记空回复 + 终止错误，让气泡显示提示卡片与重试入口。
      emptyReplyAssistantId: shouldMarkEmptyReply ? assistantMessageId : null,
      errorMessage: shouldMarkEmptyReply ? ChatErrorMessages.stoppedByUser : null,
      errorMessageAssistantId:
          shouldMarkEmptyReply ? assistantMessageId : null,
      // 收到部分内容时清空错误/空回复标记。
      clearErrorMessage: !shouldMarkEmptyReply,
      clearEmptyReply: !shouldMarkEmptyReply,
    );
    if (shouldSave) {
      saveConversation(stoppedConversation);
    }

    // 仅在确有流式会话时 complete 并清理，否则只清理残留标志。
    completeActiveStreaming(wasStreaming ? stoppedConversation : null);
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
            finishReason: streamingReply.finishReason,
          )
        : replaceAssistantMessageInTree(
            treeState: tree,
            assistantMessageId: assistantMessageId,
            nextContent: streamingReply.content,
            nextReasoningContent: streamingReply.reasoningContent,
            isStreaming: false,
            finishReason: streamingReply.finishReason,
          );

    final nextConversation = mergeStreamingResultIntoActive(
      streamingConversation: conversation,
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
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
    saveConversation(nextConversation);
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
    bool retryOnAbnormalFinishReason = false,
    Duration? streamIdleTimeout,
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
      clearEmptyReply: true,
      incrementHistoryRevision: true,
    );
    saveConversation(streamingConversation);
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
      // 双重守卫：streamStopRequested 拦截用户主动终止后的延迟回调；
      // activeStreamingCompleter != completer 拦截已被 stopStreaming 清理的旧会话；
      // completer.isCompleted 兜底防止重复完成。
      if (streamStopRequested ||
          activeStreamingCompleter != completer ||
          completer.isCompleted) {
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
        final cleanedTree = resolveMessageTreeState(streamingConversation);
        final nextTree = replaceAssistantMessageInTree(
          treeState: cleanedTree,
          assistantMessageId: assistantMessage.id,
          nextContent: '',
          nextReasoningContent: '',
          isStreaming: false,
          finishReason: streamingReply.finishReason,
        );
        // 以当前活动会话为基底合并，保留用户在流式期间改动的配置。
        final cleanedConversation = mergeStreamingResultIntoActive(
          streamingConversation: streamingConversation,
          messageNodes: nextTree.nodes,
          selectedChildByParentId: nextTree.selections,
        );
        state = state.copyWith(
          conversations: replaceConversation(cleanedConversation),
          conversationSummaries: replaceOrAddSummary(
            state.conversationSummaries,
            summaryFromConversation(cleanedConversation),
          ),
          isStreaming: false,
          emptyReplyAssistantId: assistantMessage.id,
          errorMessage: ChatErrorMessages.emptyReply,
          errorMessageAssistantId: assistantMessage.id,
          clearStreamingReply: true,
          incrementHistoryRevision: true,
        );
        saveConversation(cleanedConversation);
        completeActiveStreaming(null);
        clearActiveStreamingSession();
        return;
      }

      // 异常 finish_reason：如果启用且 finish_reason 不是正常值，走失败路径触发重试。
      // 但先检查输出规则是否清空了正文：重试仍会被同一规则清空，形成死循环，
      // 此时走输出规则清空路径（不重试）优先级更高。
      if (retryOnAbnormalFinishReason &&
          isAbnormalFinishReason(streamingReply.finishReason)) {
        final processedContent = applyOutputProcessing(streamingReply.content);
        if (processedContent.trim().isEmpty &&
            streamingReply.content.trim().isNotEmpty) {
          // 输出规则清空了正文 → 不走重试路径，提示用户检查输出处理规则。
          final cleanedTree = resolveMessageTreeState(streamingConversation);
          final nextTree = replaceAssistantMessageInTree(
            treeState: cleanedTree,
            assistantMessageId: assistantMessage.id,
            nextContent: '',
            nextReasoningContent: streamingReply.reasoningContent,
            isStreaming: false,
            finishReason: streamingReply.finishReason,
          );
          final cleanedConversation = mergeStreamingResultIntoActive(
            streamingConversation: streamingConversation,
            messageNodes: nextTree.nodes,
            selectedChildByParentId: nextTree.selections,
          );
          state = state.copyWith(
            conversations: replaceConversation(cleanedConversation),
            conversationSummaries: replaceOrAddSummary(
              state.conversationSummaries,
              summaryFromConversation(cleanedConversation),
            ),
            isStreaming: false,
            errorMessage: ChatErrorMessages.outputRuleEmptied,
            errorMessageAssistantId: assistantMessage.id,
            clearStreamingReply: true,
            incrementHistoryRevision: true,
          );
          saveConversation(cleanedConversation);
          // 返回非 null 值，阻止自动重试循环继续（重试仍会被同一规则清空）。
          completeActiveStreaming(cleanedConversation);
          clearActiveStreamingSession();
          return;
        }

        final abnormalTree = resolveMessageTreeState(streamingConversation);
        final nextTree = replaceAssistantMessageInTree(
          treeState: abnormalTree,
          assistantMessageId: assistantMessage.id,
          nextContent: processedContent,
          nextReasoningContent: streamingReply.reasoningContent,
          isStreaming: false,
          finishReason: streamingReply.finishReason,
        );
        final abnormalConversation = mergeStreamingResultIntoActive(
          streamingConversation: streamingConversation,
          messageNodes: nextTree.nodes,
          selectedChildByParentId: nextTree.selections,
        );
        state = state.copyWith(
          conversations: replaceConversation(abnormalConversation),
          conversationSummaries: replaceOrAddSummary(
            state.conversationSummaries,
            summaryFromConversation(abnormalConversation),
          ),
          isStreaming: false,
          errorMessage:
              '模型返回异常停止原因（finish_reason: ${streamingReply.finishReason}），正在自动重试...',
          errorMessageAssistantId: assistantMessage.id,
          clearStreamingReply: true,
          incrementHistoryRevision: true,
        );
        saveConversation(abnormalConversation);
        completeActiveStreaming(null);
        clearActiveStreamingSession();
        return;
      }

      // 落盘前对正文应用输出正则规则；推理内容保持原样。
      final processedContent = applyOutputProcessing(streamingReply.content);
      // 规则把原本非空的正文清空 → 提示用户检查输出处理规则，并保留占位节点。
      // 不走 emptyReply 自动重试路径：重试仍会被同一规则清空，形成死循环。
      if (processedContent.trim().isEmpty &&
          streamingReply.content.trim().isNotEmpty) {
        final cleanedTree = resolveMessageTreeState(streamingConversation);
        final nextTree = replaceAssistantMessageInTree(
          treeState: cleanedTree,
          assistantMessageId: assistantMessage.id,
          nextContent: '',
          nextReasoningContent: streamingReply.reasoningContent,
          isStreaming: false,
          finishReason: streamingReply.finishReason,
        );
        final cleanedConversation = mergeStreamingResultIntoActive(
          streamingConversation: streamingConversation,
          messageNodes: nextTree.nodes,
          selectedChildByParentId: nextTree.selections,
        );
        state = state.copyWith(
          conversations: replaceConversation(cleanedConversation),
          conversationSummaries: replaceOrAddSummary(
            state.conversationSummaries,
            summaryFromConversation(cleanedConversation),
          ),
          isStreaming: false,
          errorMessage: ChatErrorMessages.outputRuleEmptied,
          errorMessageAssistantId: assistantMessage.id,
          clearStreamingReply: true,
          incrementHistoryRevision: true,
        );
        saveConversation(cleanedConversation);
        // 返回非 null 值，阻止自动重试循环继续（重试仍会被同一规则清空）。
        completeActiveStreaming(cleanedConversation);
        clearActiveStreamingSession();
        return;
      }

      streamingReply = streamingReply.copyWith(content: processedContent);
      final streamingTree = applyStreamingReplyToConversation(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        isStreaming: false,
      );
      // 以当前活动会话为基底合并，保留用户在流式期间改动的模型/预设等配置。
      final completedConversation = mergeStreamingResultIntoActive(
        streamingConversation: streamingConversation,
        messageNodes: streamingTree.messageNodes,
        selectedChildByParentId: streamingTree.selectedChildByParentId,
      );

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
      saveConversation(completedConversation);
      completeActiveStreaming(completedConversation);
      clearActiveStreamingSession();
    }

    Future<void> completeWithError(Object error, StackTrace stackTrace) async {
      // 双重守卫：与 completeWithSuccess 保持一致，防止延迟到达的 onError
      // 在 stopStreaming 清理后绕过检查。
      if (streamStopRequested ||
          activeStreamingCompleter != completer ||
          completer.isCompleted) {
        return;
      }

      final errorMessage = formatStreamingError(error, stackTrace);
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
          streamIdleTimeout: streamIdleTimeout,
        )
        .listen(
          (chunk) {
            if (streamStopRequested) {
              return;
            }
            if (chunk.isEmpty && chunk.finishReason == null) {
              return;
            }

            responseBuffer.write(chunk.contentDelta);
            reasoningBuffer.write(chunk.reasoningDelta);
            streamingReply = streamingReply.copyWith(
              content: responseBuffer.toString(),
              reasoningContent: reasoningBuffer.toString(),
              finishReason: chunk.finishReason ?? streamingReply.finishReason,
            );
            latestStreamingReply = streamingReply;
            final now = DateTime.now();
            if (now.difference(lastUiFlushAt) < streamUiFlushInterval) {
              return;
            }

            replaceStreamingReplyInMemory(
              streamingReply.copyWith(
                content: applyOutputProcessing(streamingReply.content),
              ),
            );
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

    final tree = resolveMessageTreeState(conversation);
    // 无论是否收到内容，都保留助手占位节点：有内容则写入部分内容，
    // 无内容则写空并标记 isStreaming=false，让 UI 显示终止提示卡片与重试入口，
    // 避免直接删除节点导致用户无法重试。
    final nextTree = replaceAssistantMessageInTree(
      treeState: tree,
      assistantMessageId: streamingReply.assistantMessageId,
      nextContent: applyOutputProcessing(streamingReply.content),
      nextReasoningContent: streamingReply.reasoningContent,
      isStreaming: false,
      finishReason: streamingReply.finishReason,
    );

    return mergeStreamingResultIntoActive(
      streamingConversation: conversation,
      messageNodes: nextTree.nodes,
      selectedChildByParentId: nextTree.selections,
    );
  }

  /// 检查流式回复是否为空（无正文内容且无推理内容）。
  static bool _isEmptyStreamingReply({
    required ChatStreamingReply streamingReply,
  }) {
    return streamingReply.content.trim().isEmpty &&
        streamingReply.reasoningContent.trim().isEmpty;
  }

  /// 对模型正文应用用户配置的输出正则规则（过滤/替换）。
  ///
  /// 仅作用于正文 content，推理内容不处理。空回判定使用原始 content，
  /// 因此规则删除全部内容不会被误判为空回。
  String applyOutputProcessing(String content) {
    final rules = ref.read(outputProcessingSettingsProvider).rules;
    return applyOutputRegexRules(content, rules);
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
    // 不在此重置 streamStopRequested：延迟到达的 onDone/onError 回调仍需要
    // 该标志拦截。streamStopRequested 在下次 streamAssistantReply 开始时
    // （第 228 行）重置为 false，确保新一轮流式正常工作。
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
    RetryMode retryMode = RetryMode.perMinuteWindow,
    bool retryOnAbnormalFinishReason = false,
    bool retryOnTimeout = false,
    int timeoutSeconds = 30,
  }) async {
    final capturedGeneration = ++requestGeneration;
    autoRetryCancelled = false;
    state = state.copyWith(
      conversations: replaceConversation(pendingConversation),
      conversationSummaries: replaceOrAddSummary(
        state.conversationSummaries,
        summaryFromConversation(pendingConversation),
      ),
      clearErrorMessage: true,
      clearEmptyReply: true,
      clearAutoRetryCount: true,
      incrementHistoryRevision: true,
    );
    saveConversation(pendingConversation);

    var isFirstAttempt = true;
    while (true) {
      if (capturedGeneration != requestGeneration) return;
      if (autoRetryCancelled) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          clearErrorMessage: true,
          clearEmptyReply: true,
        );
        return;
      }

      await _waitForRetryWindow(
        isFirstAttempt: isFirstAttempt,
        overrideDelay: retryDelay,
        maxJitterMs: maxJitterMs,
        retryMode: retryMode,
      );
      isFirstAttempt = false;

      if (capturedGeneration != requestGeneration) return;
      if (autoRetryCancelled) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          clearErrorMessage: true,
          clearEmptyReply: true,
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
        clearEmptyReply: true,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      saveConversation(pendingConversation);

      if (maxRetryCount > 0 &&
          state.autoRetryCount > maxRetryCount) {
        state = state.copyWith(
          clearAutoRetryCount: true,
          errorMessage: '自动重试已达上限（$maxRetryCount 次），请检查网络或调整重试设置',
        );
        return;
      }

      if (capturedGeneration != requestGeneration) return;

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
        retryOnAbnormalFinishReason: retryOnAbnormalFinishReason,
        streamIdleTimeout: retryOnTimeout
            ? Duration(seconds: timeoutSeconds.clamp(1, 300))
            : null,
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

  /// 等待到下一个发送窗口。
  ///
  /// [RetryMode.perMinuteWindow] 下：每分钟在前 [maxJitterMs] 毫秒内随机一个时刻重试。
  /// [RetryMode.fixedInterval] 下：每隔 [maxJitterMs] 毫秒 + 随机 1000ms 抖动重试。
  Future<void> _waitForRetryWindow({
    required bool isFirstAttempt,
    Duration? overrideDelay,
    int maxJitterMs = 15000,
    RetryMode retryMode = RetryMode.perMinuteWindow,
  }) async {
    if (overrideDelay != null) {
      state = state.copyWith(isAutoRetryWaiting: true);
      await Future.delayed(overrideDelay);
      return;
    }

    if (isFirstAttempt) {
      return;
    }

    state = state.copyWith(isAutoRetryWaiting: true);

    if (retryMode == RetryMode.fixedInterval) {
      // 固定间隔：基础间隔 + 0-999ms 随机抖动
      final jitterMs = Random().nextInt(1000);
      await Future.delayed(Duration(milliseconds: maxJitterMs + jitterMs));
    } else {
      // 每分钟窗口：对齐下一分钟 + 0-(maxJitterMs-1)ms 随机抖动
      final now = DateTime.now();
      final currentSecond = now.second;
      final msToNextMinute = (60 - currentSecond) * 1000 - now.millisecond;
      final jitterMs = maxJitterMs > 0 ? Random().nextInt(maxJitterMs) : 0;
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

  /// 统一将流式错误格式化为面向开发者的详细文本（原始信息 + 堆栈）。
  ///
  /// 不做「傻瓜友好」简化：`ChatCompletionException` 附带的 HTTP 状态码、
  /// 响应体、源异常与源堆栈都会展开；其余异常直接展示 `toString()` + 堆栈。
  String formatStreamingError(Object error, StackTrace stackTrace) {
    if (error is! ChatCompletionException) {
      return formatUnexpectedStreamingError(error, stackTrace);
    }

    final buffer = StringBuffer(error.message);
    if (error.statusCode != null) {
      buffer.write('\n\nHTTP 状态码：${error.statusCode}');
    }
    final responseBody = error.responseBody?.trim();
    if (responseBody != null && responseBody.isNotEmpty) {
      buffer.write('\n\n响应体：\n```text\n${_truncateForError(responseBody)}\n```');
    }
    final cause = error.cause;
    if (cause != null) {
      buffer.write('\n\n源异常：${cause.toString().trim()}');
    }
    final causeStack = error.causeStackTrace;
    if (causeStack != null) {
      buffer.write('\n\n```text\n$causeStack\n```');
    } else {
      buffer.write('\n\n```text\n$stackTrace\n```');
    }
    return buffer.toString();
  }

  /// 响应体上限，防止超长错误体撑爆错误卡片。
  static const _maxErrorBodyLength = 4000;

  /// 截断过长文本，超出上限时保留头部并附省略提示。
  static String _truncateForError(String text) {
    if (text.length <= _maxErrorBodyLength) {
      return text;
    }
    final omitted = text.length - _maxErrorBodyLength;
    return '${text.substring(0, _maxErrorBodyLength)}\n…（已截断 $omitted 字符）';
  }
}
