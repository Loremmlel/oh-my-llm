import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_sessions_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────

  /// 创建测试用 [ChatMessage]。
  ChatMessage createMsg({
    required String id,
    required ChatMessageRole role,
    required String content,
    String reasoningContent = '',
    String? parentId,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      reasoningContent: reasoningContent,
      createdAt: DateTime(2026, 1, 1),
      parentId: parentId,
      isStreaming: isStreaming,
    );
  }

  /// 创建测试用 [ChatConversation]，messageNodes 同时作为 messages 传入，
  /// 避免 fromJson 补全线性树逻辑干扰测试。
  ChatConversation createConv({
    required String id,
    required List<ChatMessage> messageNodes,
    Map<String, String>? selections,
  }) {
    return ChatConversation(
      id: id,
      messageNodes: messageNodes,
      selectedChildByParentId: selections ?? {},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  /// 创建测试用 [ChatSessionsState]。
  ChatSessionsState createState({
    List<ChatConversation>? conversations,
    String activeConversationId = 'conv-1',
    int autoRetryCount = 0,
    String? errorMessage,
    String? errorMessageAssistantId,
    ChatStreamingReply? streamingReply,
    int historyRevision = 0,
  }) {
    return ChatSessionsState(
      conversations:
          conversations ?? [createConv(id: 'conv-1', messageNodes: [])],
      conversationSummaries: <ChatConversationSummary>[],
      activeConversationId: activeConversationId,
      autoRetryCount: autoRetryCount,
      errorMessage: errorMessage,
      errorMessageAssistantId: errorMessageAssistantId,
      streamingReply: streamingReply,
      historyRevision: historyRevision,
    );
  }

  /// 创建测试用 [ChatStreamingReply]。
  ChatStreamingReply createReply({
    String conversationId = 'conv-1',
    String assistantMessageId = 'a1',
    String content = '流式内容',
    String reasoningContent = '',
  }) {
    return ChatStreamingReply(
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      content: content,
      reasoningContent: reasoningContent,
    );
  }

  // ── ChatSessionsState.copyWith ──────────────────────────

  group('ChatSessionsState.copyWith', () {
    test('clearAutoRetryCount 将 autoRetryCount 重置为 0', () {
      final state = createState(autoRetryCount: 5);
      final result = state.copyWith(clearAutoRetryCount: true);

      expect(result.autoRetryCount, 0);
    });

    test('clearErrorMessage 将 errorMessage 设置为 null', () {
      final state = createState(errorMessage: '请求失败');
      final result = state.copyWith(clearErrorMessage: true);

      expect(result.errorMessage, isNull);
    });

    test('clearStreamingReply 将 streamingReply 设置为 null', () {
      final state = createState(streamingReply: createReply());
      final result = state.copyWith(clearStreamingReply: true);

      expect(result.streamingReply, isNull);
    });

    test('incrementHistoryRevision 将 historyRevision 加 1', () {
      final state = createState(historyRevision: 3);
      final result = state.copyWith(incrementHistoryRevision: true);

      expect(result.historyRevision, 4);
    });

    test('clearAutoRetryCount=false 时显式的 autoRetryCount 优先于原值', () {
      final state = createState(autoRetryCount: 3);
      final result = state.copyWith(autoRetryCount: 7);

      expect(result.autoRetryCount, 7);
    });

    test('clearErrorMessage=false 时显式的 errorMessage 优先于原值', () {
      final state = createState(errorMessage: '旧错误');
      final result = state.copyWith(errorMessage: '新错误');

      expect(result.errorMessage, '新错误');
    });

    test('clearErrorMessage + clearAutoRetryCount 同时生效', () {
      final state = createState(
        errorMessage: '错误发生',
        errorMessageAssistantId: 'a1',
        autoRetryCount: 5,
      );
      final result = state.copyWith(
        clearErrorMessage: true,
        clearAutoRetryCount: true,
      );

      expect(result.errorMessage, isNull);
      // clearErrorMessage 会同时清除 errorMessageAssistantId
      expect(result.errorMessageAssistantId, isNull);
      expect(result.autoRetryCount, 0);
    });
  });

  // ── applyStreamingReplyToConversation ───────────────────

  group('applyStreamingReplyToConversation', () {
    test('streamingReply 为 null 时返回原会话不变', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(id: 'u1', role: ChatMessageRole.user, content: '你好'),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: null,
      );

      expect(result, equals(conv));
    });

    test('streamingReply.conversationId 与会话 id 不匹配时返回原会话', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(id: 'a1', role: ChatMessageRole.assistant, content: '原内容'),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(
          conversationId: 'conv-other',
          assistantMessageId: 'a1',
        ),
      );

      expect(result, equals(conv));
    });

    test('匹配的 reply 更新 assistant 消息 content', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '旧内容',
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '新内容'),
      );

      final replacedNode =
          result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.content, '新内容');
      expect(replacedNode.reasoningContent, '');
    });

    test('匹配的 reply 更新 assistant 消息 reasoningContent', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '正文',
            reasoningContent: '旧推理',
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(
          content: '正文更新',
          reasoningContent: '新推理',
        ),
      );

      final replacedNode =
          result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.reasoningContent, '新推理');
      expect(replacedNode.content, '正文更新');
    });

    test('isStreaming=true 时消息上的 isStreaming 标记为 true', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '',
            isStreaming: false,
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '流式内容...'),
        isStreaming: true,
      );

      final replacedNode =
          result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.isStreaming, isTrue);
    });

    test('isStreaming=false 时消息上的 isStreaming 标记为 false', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '完整的回复',
            isStreaming: true,
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '完整的回复'),
        isStreaming: false,
      );

      final replacedNode =
          result.messageNodes.firstWhere((m) => m.id == 'a1');
      expect(replacedNode.isStreaming, isFalse);
    });

    test('空 content 和 reasoningContent 正常执行不抛异常', () {
      final conv = createConv(
        id: 'conv-1',
        messageNodes: [
          createMsg(
            id: 'a1',
            role: ChatMessageRole.assistant,
            content: '已有内容',
            parentId: rootConversationParentId,
          ),
        ],
      );

      final result = applyStreamingReplyToConversation(
        conversation: conv,
        streamingReply: createReply(content: '', reasoningContent: ''),
      );

      final replacedNode =
          result.messageNodes.firstWhere((m) => m.id == 'a1');
      // 空值被正确应用，不会抛异常
      expect(replacedNode.content, '');
      expect(replacedNode.reasoningContent, '');
    });
  });
}
