import 'dart:async';

import '../../../core/utils/id_generator.dart';
import '../../settings/domain/models/llm_model_config.dart';
import '../../settings/domain/models/prompt_template.dart';
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

  /// 终止当前流式回复，并保留已收到的部分内容。
  ///
  /// 通过取消 [StreamSubscription] 实现：取消信号向下传播至 `async*` 生成器，
  /// 中断对 SSE `ByteStream` 的监听，最终由 `dart:io` 的 `IOClient` 关闭底层
  /// TCP socket。服务器检测到连接断开后会停止生成 token。
  ///
  /// OpenAI 兼容接口没有显式的"停止生成"API 端点，关闭 TCP 连接是唯一的
  /// 标准方式。主流 LLM 服务（OpenAI、DeepSeek、Google 等）均支持此机制。
  Future<ChatConversation?> stopStreaming() async {
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
      isStreaming: false,
      clearStreamingReply: true,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await saveAllConversations();

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
      conversations: replaceConversation(nextConversation),
      isStreaming: false,
      errorMessage: errorMessage,
      clearStreamingReply: true,
      incrementHistoryRevision: true,
    );
    await saveAllConversations();
  }

  /// 把 assistant 回复以流式方式写回当前会话。
  Future<ChatConversation?> streamAssistantReply({
    required ChatConversation conversation,
    required LlmModelConfig modelConfig,
    required PromptTemplate? promptTemplate,
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
    streamStopRequested = false;

    state = state.copyWith(
      conversations: replaceConversation(streamingConversation),
      isStreaming: true,
      streamingReply: streamingReply,
      clearErrorMessage: true,
      incrementHistoryRevision: true,
    );
    await saveAllConversations();

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

      final completedConversation = applyStreamingReplyToConversation(
        conversation: streamingConversation,
        streamingReply: streamingReply,
        isStreaming: false,
      ).copyWith(updatedAt: DateTime.now());

      state = state.copyWith(
        conversations: replaceConversation(completedConversation),
        isStreaming: false,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      await saveAllConversations();
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
            promptTemplate: promptTemplate,
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

    state = state.copyWith(streamingReply: streamingReply, isStreaming: true);
  }

  ChatConversation buildConversationAfterStreamingInterrupt({
    required ChatConversation conversation,
    required ChatStreamingReply? streamingReply,
  }) {
    if (streamingReply == null) {
      return conversation.copyWith(updatedAt: DateTime.now());
    }

    final hasPartialContent =
        streamingReply.content.trim().isNotEmpty ||
        streamingReply.reasoningContent.trim().isNotEmpty;
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
