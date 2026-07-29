import '../../settings/application/output_processing_settings_controller.dart';
import '../../settings/domain/models/auto_retry_settings.dart';
import '../data/chat_completion_client.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/chat_error_messages.dart';
import '../domain/models/chat_message.dart';
import 'chat_message_tree.dart';
import 'chat_sessions_controller_support.dart';
import 'chat_sessions_state.dart';
import 'output_regex_processor.dart';

/// 为 [ChatSessionsController] 提供流式与终态投影辅助。
///
/// 只保留无 generation 状态的纯投影/格式化 helper：流式增量刷新、输出正则、
/// 终态分支（成功/空回复/异常 finish/失败）与错误格式化。generation 的异步
/// 时序、attempt、retry、cancel 由 [ChatGenerationCoordinator] 独占；controller
/// 通过桥接字段与之协作，不再经 mixin 持有 subscription/completer/取消标志。
mixin ChatSessionsControllerStreaming on ChatSessionsControllerSupport {
  static const streamUiFlushInterval = Duration(milliseconds: 300);

  /// 在流式请求失败时，保留已生成内容或清除空白占位节点。
  Future<void> handleStreamingFailure({
    required ChatConversation conversation,
    required ChatStreamingReply streamingReply,
    required String assistantMessageId,
    required String errorMessage,
  }) async {
    final tree = resolveMessageTreeState(conversation);
    final isEmpty =
        streamingReply.content.trim().isEmpty &&
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
    // durable save 由 _handleGenerationDecision（AttemptFailed -> null 分支）统一 await。
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

  /// 对模型正文应用用户配置的输出正则规则（过滤/替换）。
  ///
  /// 仅作用于正文 content，推理内容不处理。空回判定使用原始 content，
  /// 因此规则删除全部内容不会被误判为空回。
  String applyOutputProcessing(String content) {
    final rules = ref.read(outputProcessingSettingsProvider).rules;
    return applyOutputRegexRules(content, rules);
  }

  /// 处理流式回复成功完成的决策逻辑（5 分支）。
  ///
  /// 包含 5 个分支：
  /// 1. 空回复
  /// 2. 异常 finish + 输出规则清空
  /// 3. 异常 finish + 未清空
  /// 4. 正常 + 输出规则清空
  /// 5. 正常完成
  ///
  /// [skipEmptyCheck] 为 true 时跳过分支 1，适用于 coordinator 已独立处理
  /// emptyReply 的场景。
  Future<ChatConversation?> finishGenerationSuccess({
    required ChatConversation streamingConversation,
    required ChatMessage assistantMessage,
    required ChatStreamingReply streamingReply,
    required bool retryOnAbnormalFinishReason,
    bool skipEmptyCheck = false,
  }) async {
    // 分支 1：空回复
    if (!skipEmptyCheck &&
        streamingReply.content.trim().isEmpty &&
        streamingReply.reasoningContent.trim().isEmpty) {
      final cleanedTree = resolveMessageTreeState(streamingConversation);
      final nextTree = replaceAssistantMessageInTree(
        treeState: cleanedTree,
        assistantMessageId: assistantMessage.id,
        nextContent: '',
        nextReasoningContent: '',
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
        emptyReplyAssistantId: assistantMessage.id,
        errorMessage: ChatErrorMessages.emptyReply,
        errorMessageAssistantId: assistantMessage.id,
        clearStreamingReply: true,
        incrementHistoryRevision: true,
      );
      // durable save 由 _handleGenerationDecision 统一 await。
      return null;
    }

    // 分支 2/3：异常 finish_reason
    if (retryOnAbnormalFinishReason &&
        isAbnormalFinishReason(streamingReply.finishReason)) {
      final processedContent = applyOutputProcessing(streamingReply.content);
      if (processedContent.trim().isEmpty &&
          streamingReply.content.trim().isNotEmpty) {
        // 分支 2：输出规则清空了正文，不走重试路径。
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
        // durable save 由 _handleGenerationDecision 统一 await。
        return cleanedConversation;
      }

      // 分支 3：异常 finish 未清空，返回 null 触发 caller 重试。
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
      // durable save 由 _handleGenerationDecision 统一 await。
      return null;
    }

    // 分支 4：正常 + 输出规则清空
    final processedContent = applyOutputProcessing(streamingReply.content);
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
      // durable save 由 _handleGenerationDecision 统一 await。
      return cleanedConversation;
    }

    // 分支 5：正常完成
    final streamingContent = streamingReply.copyWith(content: processedContent);
    final streamingTree = applyStreamingReplyToConversation(
      conversation: streamingConversation,
      streamingReply: streamingContent,
      isStreaming: false,
    );
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
    // durable save 由 _handleGenerationDecision 统一 await。
    return completedConversation;
  }

  /// 处理流式回复失败：格式化错误 + handleStreamingFailure。
  ///
  /// caller 负责在调用前先 complete completer 并清理会话字段。
  Future<void> finishGenerationError({
    required ChatConversation streamingConversation,
    required ChatStreamingReply? streamingReply,
    required ChatMessage assistantMessage,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    final errorMessage = formatStreamingError(error, stackTrace);
    await handleStreamingFailure(
      conversation: streamingConversation,
      streamingReply:
          streamingReply ??
          ChatStreamingReply(
            conversationId: streamingConversation.id,
            assistantMessageId: assistantMessage.id,
          ),
      assistantMessageId: assistantMessage.id,
      errorMessage: errorMessage,
    );
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
      buffer.write(
        '\n\n响应体：\n```text\n${_truncateForError(responseBody)}\n```',
      );
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
